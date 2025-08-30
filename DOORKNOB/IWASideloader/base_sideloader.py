import os
import base64
import uuid
from abc import ABC, abstractmethod
from reference.bundleParser import parse_signed_web_bundle_header, extract_manifest_from_bundle
from reference.getAppId import create_web_bundle_id_from_public_key, get_chrome_app_id
from reference.protobufUpdater import parse_protobuf, update_with_origin
import binascii
import random
from datetime import datetime


class BaseSideloader(ABC):
    """Base class for platform-specific sideloaders."""
    
    def __init__(self, bundle_path, app_name="DOORKNOB"):
        self.bundle_path = bundle_path
        self.app_name = app_name
        self.bundle_data = None
        self.protobuf_hex = None
        self.app_id = None
        self.iwa_folder_name = None
        self.iwa_tab_url = None
        
        # Load bundle data and generate required values
        self._load_bundle_data()
        self._generate_protobuf_data()
    
    def _load_bundle_data(self):
        """Load and base64 encode the bundle file."""
        with open(self.bundle_path, 'rb') as f:
            self.bundle_data = base64.b64encode(f.read()).decode('ascii')
    
    def _generate_protobuf_data(self):
        """Generate protobuf data using information from manifest and bundle."""
        # Read manifest from bundle
        manifest = extract_manifest_from_bundle(self.bundle_path)
        app_name = manifest['name']
        version = manifest['version']
        
        # Parse bundle to get signature and public key
        bundle_info = parse_signed_web_bundle_header(self.bundle_path)
        public_key = bundle_info['public_key']
        signature_info = bundle_info['signature']
        
        # Generate IDs from public key
        web_bundle_id = create_web_bundle_id_from_public_key(base64.b64decode(public_key))
        origin = f"isolated-app://{web_bundle_id}"
        self.iwa_tab_url = origin
        self.app_id = get_chrome_app_id(public_key)
        
        # Generate other required values
        install_time = int(datetime.now().timestamp())
        self.iwa_folder_name = "".join(random.choices("abcdefghijklmnopqrstuvwxyz0123456789", k=16))
        
        # Print information
        print("Generated values:")
        print(f"APP_NAME: {app_name}")
        print(f"VERSION: {version}")
        print(f"ORIGIN: {origin}")
        print(f"APP_ID: {self.app_id}")
        print(f"PUBLIC_KEY: {public_key}")
        print(f"SIGNATURE_INFO: {signature_info}")
        print(f"IWA_FOLDER_NAME: {self.iwa_folder_name}")
        print(f"IWA_ORIGIN: {self.iwa_tab_url}")
        
        # Read template protobuf
        script_dir = os.path.dirname(os.path.abspath(__file__))
        template_path = os.path.join(script_dir, "reference", "app.pb")
        with open(template_path, 'rb') as f:
            template_data = f.read()
        
        # Parse and update protobuf
        message = parse_protobuf(template_data)
        
        # Convert string values to bytes for length-delimited fields
        def to_bytes(s: str) -> bytes:
            return s.encode('utf-8')
        
        # Track jitter count for field 59.1.3.2
        jitter_count = 0
        def add_jitter(base_time: int, _) -> int:
            nonlocal jitter_count
            jitter_count += 1
            return base_time + jitter_count + random.randint(5, 10)
        
        # Perform field updates
        updates = [
            ([1, 1], to_bytes(f"{origin}/")),
            ([1, 2], to_bytes(app_name)),
            ([1, 5], to_bytes(f"{origin}/")),
            ([1, 6, 2], origin, update_with_origin),
            ([2], to_bytes(app_name)),
            ([6], to_bytes(f"{origin}/")),
            ([10, 2], origin, update_with_origin),
            ([16], install_time),
            ([30], origin, update_with_origin),
            ([49, 2], to_bytes(origin)),
            ([59, 1, 3, 2], install_time, add_jitter),
            ([59, 1, 1], to_bytes(app_name)),
            ([59, 5, 2], to_bytes(app_name)),
            ([60, 1, 1], to_bytes(self.iwa_folder_name)),
            ([60, 6], to_bytes(version)),
            ([60, 7, 1, 1, 1], to_bytes(public_key)),
            ([60, 7, 1, 1, 2], to_bytes(signature_info)),
            ([64], install_time),
        ]
        
        for field_path, value, *transform in updates:
            message.update_field(field_path, value, transform[0] if transform else None)
        
        # Serialize
        serialized = message.serialize()
        self.protobuf_hex = binascii.hexlify(serialized).decode('ascii')
    
    @abstractmethod
    def get_platform_config(self):
        """Return platform-specific configuration."""
        pass
    
    @abstractmethod
    def generate_script(self, output_path):
        """Generate the platform-specific sideloader script."""
        pass
    
    def generate_guid(self):
        """Generate a GUID for desktop/session naming."""
        return str(uuid.uuid4())
