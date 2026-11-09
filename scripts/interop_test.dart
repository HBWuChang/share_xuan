// Run with the existing Listen1 package configuration; exercises its real disk receiver.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../listen1_xuan/lib/services/paste_file_transfer.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('share-xuan-interop-');
  final executable = File.fromUri(Platform.script.resolve('../TransferCore/.build/debug/TransferProbe')).path;
  final fixture = File('${root.path}/中文 空格.bin');
  final bytes = List<int>.generate(1024 * 1024 + 17, (i) => i % 251);
  await fixture.writeAsBytes(bytes);
  final http = HttpClient();
  Process? native;
  HttpServer? dartServer;
  WebSocket? ws;
  final logs = <String>[];
  try {
    final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservation.port; await reservation.close();
    native = await Process.start(executable, [fixture.path], environment: {'PROBE_ROOT': '${root.path}/native-server', 'PROBE_PORT': '$port'});
    final ready = Completer<void>();
    native.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) { logs.add(line); if (line == 'READY' && !ready.isCompleted) ready.complete(); });
    native.stderr.transform(utf8.decoder).listen((line) => logs.add('STDERR:$line'));
    await ready.future.timeout(const Duration(seconds: 15));
    ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final welcome = Completer<void>(), offer = Completer<void>(), pong = Completer<void>(), serverText = Completer<void>();
    ws.listen((data) {
      final msg = jsonDecode(data as String);
      switch (msg['type']) {
        case 'welcome': if (!welcome.isCompleted) welcome.complete();
        case 'reqToGetFile': if (!offer.isCompleted) offer.complete();
        case 'pong': if (!pong.isCompleted) pong.complete();
        case 'sendPasteText': check(msg['content'] == '来自 share_xuan', 'server text'); if (!serverText.isCompleted) serverText.complete();
      }
    });
    await welcome.future.timeout(const Duration(seconds: 5));
    ws.add(jsonEncode({'type': 'ping', 'content': '{}'}));
    ws.add(jsonEncode({'type': 'sendPasteText', 'content': '来自 Dart Listen1'}));
    await pong.future.timeout(const Duration(seconds: 5));
    // Chunked multipart request matching Dio's file upload format.
    final request = await http.post('127.0.0.1', port, '/onPasteFile');
    request.headers.set('content-type', 'multipart/form-data; boundary=test-boundary');
    request.add(utf8.encode('--test-boundary\r\nContent-Disposition: form-data; name="files"; filename="来自Dart.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'));
    await request.addStream(fixture.openRead());
    request.write('\r\n--test-boundary--\r\n');
    final response = await request.close(); check(response.statusCode == 200, 'native upload status ${response.statusCode}'); await response.drain<void>();
    final uploaded = await Directory('${root.path}/native-server/Inbox').list(recursive: true).where((e) => e is File).cast<File>().first;
    check(base64Encode(await uploaded.readAsBytes()) == base64Encode(bytes), 'native received bytes');
    final imageReq = await http.post('127.0.0.1', port, '/onPasteImage');
    imageReq.headers.set('x-filename', Uri.encodeComponent('图片.png')); imageReq.add([0, 1, 2, 255]);
    final imageResp = await imageReq.close(); check(imageResp.statusCode == 200, 'raw image upload'); await imageResp.drain<void>();
    await offer.future.timeout(const Duration(seconds: 5));
    final get = await http.get('127.0.0.1', port, '/getPasteFile'); final getResponse = await get.close();
    check(getResponse.statusCode == 200, 'native download status');
    final saved = await PasteFileTransfer.receive(stream: getResponse, saveDir: '${root.path}/dart-received', boundary: PasteFileTransfer.boundaryFromContentType(getResponse.headers.value('content-type')!));
    check(saved.single.endsWith(fixture.uri.pathSegments.last), 'unicode filename');
    check(base64Encode(await File(saved.single).readAsBytes()) == base64Encode(bytes), 'Listen1 parser received bytes');
    await serverText.future.timeout(const Duration(seconds: 5));
    check(logs.any((line) => line == 'TEXT:来自 Dart Listen1'), 'native received text');
    await ws.close(); native.kill(); await native.exitCode; native = null;
    print('PASS: Swift server ↔ Dart WebSocket + actual Listen1 multipart receiver (text, ping, file, image, Unicode, binary)');

    // A Dart HttpServer speaks Listen1's exact wire protocol to the native client.
    dartServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gotText = Completer<void>(), gotPong = Completer<void>(), gotUpload = Completer<void>();
    dartServer.listen((request) async {
      try {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((data) {
            final msg = jsonDecode(data as String);
            if (msg['type'] == 'sendPasteText' && msg['content'] == '来自原生客户端' && !gotText.isCompleted) gotText.complete();
            if (msg['type'] == 'pong' && !gotPong.isCompleted) gotPong.complete();
          });
          for (final msg in [
            {'type': 'welcome', 'content': jsonEncode({'deviceId': 'dart-listen1'})},
            {'type': 'ping', 'content': '{}'},
            {'type': 'sendPasteText', 'content': '来自Dart服务器'},
            {'type': 'reqToGetFile', 'content': jsonEncode([fixture.uri.pathSegments.last])},
          ]) { socket.add(jsonEncode(msg)); }
          Future<void>.delayed(const Duration(seconds: 3), () { if (socket.readyState == WebSocket.open) socket.add(jsonEncode({'type': 'reqToGetImage', 'content': '测试图片.png'})); });
        } else if (request.uri.path == '/onPasteFile') {
          final files = await PasteFileTransfer.receive(stream: request, saveDir: '${root.path}/dart-server', boundary: PasteFileTransfer.boundaryFromContentType(request.headers.value('content-type')!));
          check(base64Encode(await File(files.single).readAsBytes()) == base64Encode(bytes), 'native client upload bytes');
          request.response.headers.contentType = ContentType.json; request.response.write('{"saved":1}'); await request.response.close(); gotUpload.complete();
        } else if (request.uri.path == '/getPasteFile') {
          request.response.headers.set('content-type', 'multipart/mixed; boundary=dart-response');
          request.response.write("--dart-response\r\nContent-Disposition: attachment; filename*=UTF-8''${Uri.encodeComponent(fixture.uri.pathSegments.last)}\r\nContent-Type: application/octet-stream\r\nContent-Length: ${bytes.length}\r\n\r\n");
          await request.response.addStream(fixture.openRead()); request.response.write('\r\n--dart-response--\r\n'); await request.response.close();
        } else if (request.uri.path == '/getPasteImage') {
          request.response.headers.set('content-disposition', "attachment; filename*=UTF-8''${Uri.encodeComponent('测试图片.png')}");
          request.response.add([0, 1, 2, 255]); await request.response.close();
        } else { request.response.statusCode = 404; await request.response.close(); }
      } catch (error, stack) { stderr.writeln('$error\n$stack'); if (!gotUpload.isCompleted) gotUpload.completeError(error, stack); }
    });
    final nativeClient = await Process.run(executable, ['client', '127.0.0.1:${dartServer.port}', fixture.path], environment: {'PROBE_ROOT': '${root.path}/native-client'});
    check(nativeClient.exitCode == 0, 'native client exit: ${nativeClient.stdout}\n${nativeClient.stderr}');
    await Future.wait([gotText.future, gotPong.future, gotUpload.future]).timeout(const Duration(seconds: 10));
    check(nativeClient.stdout.toString().contains('TEXT:来自Dart服务器'), 'client text received');
    final clientFiles = await Directory('${root.path}/native-client/Inbox').list(recursive: true).where((e) => e is File).cast<File>().toList();
    check(clientFiles.length == 2, 'native client received file and image: ${nativeClient.stdout}');
    final receivedFile = clientFiles.firstWhere((file) => file.path.endsWith('.bin'));
    check(base64Encode(await receivedFile.readAsBytes()) == base64Encode(bytes), 'native client download bytes');
    check(base64Encode(await clientFiles.firstWhere((file) => file.path.endsWith('.png')).readAsBytes()) == base64Encode([0, 1, 2, 255]), 'native client image bytes');
    print('PASS: Swift client ↔ Dart Listen1 protocol (welcome, ping/pong, text, upload, file/image download)');
  } finally {
    http.close(force: true); await ws?.close(); native?.kill(); await dartServer?.close(force: true); await root.delete(recursive: true);
  }
}
