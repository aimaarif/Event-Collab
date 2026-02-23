import 'package:flutter/material.dart';
import 'package:event_collab/config/api_config.dart';
import 'package:event_collab/services/huggingface_service.dart';

class AiChatbotScreen extends StatefulWidget {
  @override
  _AiChatbotScreenState createState() => _AiChatbotScreenState();
}

class _AiChatbotScreenState extends State<AiChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  late HuggingFaceService? _aiService;
  bool _isLoading = false;
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    _hasToken = huggingFaceApiToken.isNotEmpty;
    if (_hasToken) {
      _aiService = HuggingFaceService(apiToken: huggingFaceApiToken);
      _messages.add({
        'role': 'assistant',
        'content': 'Hi! I\'m your Event Collab assistant. Ask me about events, how to use the app, or anything else!',
      });
    } else {
      _messages.add({
        'role': 'assistant',
        'content': 'To use the AI chatbot, add your Hugging Face API token. Get a free token at huggingface.co/settings/tokens and run the app with: flutter run --dart-define=HF_TOKEN=your_token',
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _aiService?.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || !_hasToken) return;

    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _scrollToBottom();

    final history = _messages
        .where((m) => m['role'] != null && m['content'] != null)
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    final response = await _aiService!.chat(text, conversationHistory: history);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _messages.add({
          'role': 'assistant',
          'content': response ?? 'Sorry, I couldn\'t generate a response. Please try again.',
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: Colors.white),
            SizedBox(width: 8),
            Text('AI Assistant'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).primaryColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    child: Text(
                      msg['content'] ?? '',
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Thinking...', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: _hasToken ? 'Ask me anything...' : 'Add HF token to chat',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: _hasToken && !_isLoading,
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _hasToken && !_isLoading ? _sendMessage : null,
                    icon: Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
