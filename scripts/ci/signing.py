"""Ephemeral GitHub macOS signing setup. Never prints decoded secrets."""
import base64
import datetime
import json
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def validate_profile(profile, bundle, team, group):
    entitlements = profile.get('Entitlements', {})
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    if profile.get('TeamIdentifier') != [team]:
        raise ValueError('Provisioning profile belongs to a different team')
    if entitlements.get('application-identifier') not in [p + '.' + bundle for p in prefixes]:
        raise ValueError('Provisioning profile Bundle ID does not match ' + bundle)
    if group not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError('Provisioning profile does not include the configured App Group')
    if entitlements.get('get-task-allow', False) or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices', False):
        raise ValueError('Use an App Store Connect distribution profile, not Development/Ad Hoc/Enterprise')
    expiration = profile.get('ExpirationDate')
    if not isinstance(expiration, datetime.datetime) or expiration.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Provisioning profile expired')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', profile.get('UUID', '')):
        raise ValueError('Invalid profile UUID')
    if not profile.get('DeveloperCertificates'):
        raise ValueError('Provisioning profile has no signing certificates')
    return profile['UUID']


def patch_profiles(text, app_uuid, share_uuid):
    counts = [0, 0]
    def patch(match):
        block = match.group(0)
        for index, (variable, uuid) in enumerate([('APP_BUNDLE_IDENTIFIER', app_uuid), ('SHARE_BUNDLE_IDENTIFIER', share_uuid)]):
            if 'PRODUCT_BUNDLE_IDENTIFIER = "$(' + variable + ')";' in block:
                block = re.sub(r'^\s*PROVISIONING_PROFILE_SPECIFIER = .*;\n', '', block, flags=re.MULTILINE)
                block = block.replace('buildSettings = {', 'buildSettings = {\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "' + uuid + '";', 1)
                counts[index] += 1
        return block
    patched = re.sub(r'buildSettings = \{.*?\n\s*\};', patch, text, flags=re.DOTALL)
    if counts != [2, 2]:
        raise ValueError('Unexpected Xcode signing layout; expected Debug/Release for both targets')
    return patched


def prepare(root):
    required = ['APPLE_TEAM_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_BASE64',
                'DISTRIBUTION_P12_BASE64', 'DISTRIBUTION_P12_PASSWORD', 'APP_PROFILE_BASE64', 'SHARE_PROFILE_BASE64']
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise ValueError('Missing GitHub environment configuration: ' + ', '.join(missing))
    if not re.fullmatch(r'[A-Za-z0-9]+', os.environ['ASC_KEY_ID']):
        raise ValueError('Invalid ASC_KEY_ID')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    config = {}
    for line in Path('Config.xcconfig').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('//'):
            key, value = line.split('=', 1)
            config[key.strip()] = value.strip()
    team = os.environ['APPLE_TEAM_ID']
    def decode(name, target):
        target.write_bytes(base64.b64decode(''.join(os.environ[name].split()), validate=True))
        target.chmod(0o600)
    keychain = root / 'signing.keychain-db'
    old_keychains = shlex.split(run('security', 'list-keychains', '-d', 'user').decode())
    # Write cleanup state before installing anything.
    state = {'keychains': old_keychains, 'profiles': []}
    state_path = root / 'state.json'
    state_path.write_text(json.dumps(state))
    password = secrets.token_urlsafe(32)
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    p12 = root / 'distribution.p12'
    decode('DISTRIBUTION_P12_BASE64', p12)
    run('security', 'import', str(p12), '-P', os.environ['DISTRIBUTION_P12_PASSWORD'], '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *old_keychains)
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)).decode()
    if not re.search(r'"Apple Distribution:', identities):
        raise ValueError('P12 must include a valid Apple Distribution certificate and its private key')
    uuids = []
    profile_dir = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    profile_dir.mkdir(parents=True, exist_ok=True)
    for secret, bundle in [('APP_PROFILE_BASE64', config['APP_BUNDLE_IDENTIFIER']), ('SHARE_PROFILE_BASE64', config['SHARE_BUNDLE_IDENTIFIER'])]:
        source = root / (secret + '.mobileprovision')
        decode(secret, source)
        profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(source)))
        uuid = validate_profile(profile, bundle, team, config['APP_GROUP_IDENTIFIER'])
        if not any(hashlib.sha1(cert).hexdigest().upper() in identities for cert in profile['DeveloperCertificates']):
            raise ValueError('Provisioning profile does not include the imported Distribution certificate')
        destination = profile_dir / (uuid + '.mobileprovision')
        if destination.exists():
            raise ValueError('Profile already exists on runner; refusing to overwrite it')
        state['profiles'].append(str(destination)); state_path.write_text(json.dumps(state))
        shutil.copyfile(source, destination); destination.chmod(0o600)
        uuids.append(uuid)
    project = Path('share_xuan.xcodeproj/project.pbxproj')
    (root / 'project.pbxproj.original').write_bytes(project.read_bytes())
    project.write_text(patch_profiles(project.read_text(), *uuids))
    export = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
              'teamID': team, 'signingCertificate': 'Apple Distribution', 'manageAppVersionAndBuildNumber': False,
              'provisioningProfiles': dict(zip([config['APP_BUNDLE_IDENTIFIER'], config['SHARE_BUNDLE_IDENTIFIER']], uuids))}
    (root / 'ExportOptions.plist').write_bytes(plistlib.dumps(export))
    private = root / 'private_keys'; private.mkdir(mode=0o700)
    decode('ASC_PRIVATE_KEY_BASE64', private / ('AuthKey_' + os.environ['ASC_KEY_ID'] + '.p8'))
    print('Signing profiles validated and installed for both targets.')


def cleanup(root):
    state_path = root / 'state.json'
    if state_path.exists():
        state = json.loads(state_path.read_text())
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *state['keychains']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for profile in state['profiles']:
            Path(profile).unlink(missing_ok=True)
    keychain = root / 'signing.keychain-db'
    if keychain.exists():
        subprocess.run(['security', 'delete-keychain', str(keychain)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    original = root / 'project.pbxproj.original'
    if original.exists():
        Path('share_xuan.xcodeproj/project.pbxproj').write_bytes(original.read_bytes())
    shutil.rmtree(root, ignore_errors=True)


if __name__ == '__main__':
    try:
        if not os.environ.get('RUNNER_TEMP') or os.environ.get('GITHUB_ACTIONS') != 'true':
            raise ValueError('Signing setup is intended only for an ephemeral GitHub-hosted runner')
        root = Path(os.environ['RUNNER_TEMP']) / 'share-xuan-signing'
        if sys.argv[1:] == ['prepare']:
            prepare(root)
        elif sys.argv[1:] == ['cleanup']:
            cleanup(root)
        else:
            raise ValueError('Usage: signing.py prepare|cleanup')
    except subprocess.CalledProcessError:
        # Commands can contain passwords; never print CalledProcessError/argv.
        print('Apple signing command failed. Check certificate password, validity and profile setup.', file=sys.stderr)
        sys.exit(1)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
