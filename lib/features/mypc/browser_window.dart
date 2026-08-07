// Окно браузера в "Моём ПК": адресная строка + реальный WebView.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrowserWindow extends StatefulWidget {
  const BrowserWindow({super.key});

  @override
  State<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends State<BrowserWindow> {
  late final WebViewController _controller;
  final _address = TextEditingController(text: 'https://www.google.com');

  static const _homeUrl = 'https://www.google.com';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..loadRequest(Uri.parse(_homeUrl));
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _go() {
    var url = _address.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _controller.loadRequest(Uri.parse(url));
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            color: const Color(0xFFE5E5E5),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _controller.goBack(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _controller.goForward(),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _controller.reload(),
                  icon: const Icon(Icons.refresh, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () {
                    _address.text = _homeUrl;
                    _controller.loadRequest(Uri.parse(_homeUrl));
                  },
                  icon: const Icon(Icons.home, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _address,
                      onSubmitted: (_) => _go(),
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _go,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
