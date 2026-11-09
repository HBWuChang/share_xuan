import copy
import datetime
from pathlib import Path
import unittest
from signing import patch_profiles, validate_profile


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            'UUID': '12345678-1234-1234-1234-123456789abc',
            'TeamIdentifier': ['TEAM'], 'ApplicationIdentifierPrefix': ['PREFIX'],
            'ExpirationDate': datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30),
            'DeveloperCertificates': [b'test'],
            'Entitlements': {'application-identifier': 'PREFIX.xyz.040905.share',
                             'com.apple.security.application-groups': ['group.xyz.040905.share'],
                             'get-task-allow': False},
        }

    def validate(self, value):
        return validate_profile(value, 'xyz.040905.share', 'TEAM', 'group.xyz.040905.share')

    def test_distribution_profile_and_distinct_prefix(self):
        self.assertEqual(self.validate(self.profile), self.profile['UUID'])

    def test_reject_wrong_target_team_group_and_expired_profiles(self):
        variants = []
        for key, value in [('TeamIdentifier', ['OTHER']), ('ExpirationDate', datetime.datetime(2020, 1, 1)), ('ProvisionedDevices', ['phone']), ('ProvisionsAllDevices', True), ('DeveloperCertificates', [])]:
            profile = copy.deepcopy(self.profile); profile[key] = value; variants.append(profile)
        for key, value in [('application-identifier', 'PREFIX.xyz.040905.share.ShareExtension'), ('com.apple.security.application-groups', []), ('get-task-allow', True)]:
            profile = copy.deepcopy(self.profile); profile['Entitlements'][key] = value; variants.append(profile)
        for profile in variants:
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                self.validate(profile)

    def test_target_specific_profile_patch_and_idempotence(self):
        source = Path('share_xuan.xcodeproj/project.pbxproj').read_text()
        app = '12345678-1234-1234-1234-123456789abc'
        share = '22345678-1234-1234-1234-123456789abc'
        patched = patch_profiles(source, app, share)
        self.assertEqual(patched.count('PROVISIONING_PROFILE_SPECIFIER = "' + app + '"'), 2)
        self.assertEqual(patched.count('PROVISIONING_PROFILE_SPECIFIER = "' + share + '"'), 2)
        self.assertEqual(patch_profiles(patched, app, share), patched)
        with self.assertRaises(ValueError):
            patch_profiles('invalid project', app, share)


if __name__ == '__main__':
    unittest.main()
