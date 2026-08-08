// Простой браузер для открытия источников из «Поиска» (webview_flutter).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';

class WebViewScreen extends StatefulWidget {
  final String url;

  const WebViewScreen({super.key, required this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      );
    final uri = Uri.parse(widget.url);
    if (uri.scheme == 'file') {
      // Статья System: Hermes (HTML из «Поиска»).
      _controller.loadFile(uri.toFilePath());
    } else {
      _controller.loadRequest(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Источник'),
        actions: [
          IconButton(
            tooltip: 'Копировать ссылку',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.url));
              if (context.mounted) toast(context, 'Ссылка скопирована');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_loading)
            Positioned(
              bottom: 8,
              left: 16,
              right: 16,
              child: Text(
                widget.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
