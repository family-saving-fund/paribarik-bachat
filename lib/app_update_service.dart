import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final int latestVersionCode;
  final String latestVersion;
  final String apkUrl;
  final bool forceUpdate;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.latestVersionCode,
    required this.latestVersion,
    required this.apkUrl,
    required this.forceUpdate,
    required this.releaseNotes,
  });
}

class AppUpdateService {
  static const String _githubOwner = 'family-saving-fund';
  static const String _githubRepository = 'paribarik-bachat-kosh-apk-';
  static const String _latestReleaseApi =
      'https://api.github.com/repos/$_githubOwner/$_githubRepository/releases/latest';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http.get(
        Uri.parse(_latestReleaseApi),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Paribarik-Bachat-Kosh-Android-App',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;
      final release = jsonDecode(response.body);
      if (release is! Map<String, dynamic> ||
          release['draft'] == true ||
          release['prerelease'] == true) {
        return null;
      }

      final tag = (release['tag_name'] as String? ?? '').trim();
      final body = (release['body'] as String? ?? '').trim();
      final versionCode = _readVersionCode(tag, body);
      if (versionCode == null || versionCode <= installedBuild) return null;

      final assets = release['assets'];
      if (assets is! List) return null;
      final apkAssets = assets.whereType<Map<String, dynamic>>().where((asset) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        return name.endsWith('.apk');
      }).toList();
      if (apkAssets.isEmpty) return null;

      // The release workflow publishes one universal APK. Prefer it if more
      // than one APK asset is ever attached to a release.
      apkAssets.sort((a, b) {
        final an = (a['name'] as String? ?? '').toLowerCase();
        final bn = (b['name'] as String? ?? '').toLowerCase();
        final ap = an.contains('universal') ? 0 : 1;
        final bp = bn.contains('universal') ? 0 : 1;
        return ap.compareTo(bp);
      });

      final apkUrl = apkAssets.first['browser_download_url'] as String? ?? '';
      final uri = Uri.tryParse(apkUrl);
      if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
        return null;
      }

      final releaseName = (release['name'] as String? ?? '').trim();
      final version = releaseName.isNotEmpty
          ? releaseName
          : tag.replaceFirst(RegExp(r'^v'), '');
      final forceUpdate = RegExp(
        r'^\s*Force Update\s*:\s*true\s*$',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(body);

      return AppUpdateInfo(
        latestVersionCode: versionCode,
        latestVersion: version,
        apkUrl: apkUrl,
        forceUpdate: forceUpdate,
        releaseNotes: body,
      );
    } catch (_) {
      // Update checks must never prevent the member from opening the app.
      return null;
    }
  }

  static int? _readVersionCode(String tag, String releaseNotes) {
    final notesMatch = RegExp(
      r'^\s*Version Code\s*:\s*(\d+)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(releaseNotes);
    if (notesMatch != null) return int.tryParse(notesMatch.group(1)!);

    final tagMatch = RegExp(r'\+(\d+)$').firstMatch(tag);
    if (tagMatch != null) return int.tryParse(tagMatch.group(1)!);
    return null;
  }

  static Future<bool> downloadAndInstall(String apkUrl) async {
    try {
      final uri = Uri.tryParse(apkUrl);
      if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
        return false;
      }

      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'Paribarik-Bachat-Kosh-Android-App'},
      ).timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.length < 1024 * 1024) {
        return false;
      }

      final bytes = response.bodyBytes;
      // APK files are ZIP containers. Reject HTML error pages or other content.
      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4B ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        return false;
      }

      final directory = await getApplicationSupportDirectory();
      final apkFile = File('${directory.path}/paribarik-bachat-kosh-update.apk');
      if (await apkFile.exists()) await apkFile.delete();
      await apkFile.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }
}
