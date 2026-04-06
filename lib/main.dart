import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String correctedText = "";
  List<Map<String, String>> mistakes = [];
  bool isLoading = false;
  bool isEditing = false;
  bool isResultMode = false;
  final TextEditingController _textController = TextEditingController();

  static const String groqApiKey = "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";

  // ✅ AI 첨삭 함수
  Future<void> getAiFeedback(String text) async {
    setState(() { isLoading = true; isEditing = false; });
    const String url = "https://api.groq.com/openai/v1/chat/completions";
    final prompt = """
너는 Write Buddy 앱의 교정 엔진이야. 다음 영어 문장을 분석해서 반드시 아래 JSON 형식으로만 답해줘. 한국어로 설명해.
{
  "corrected_text": "전체 교정 문장",
  "mistakes": [
    {"wrong": "틀린단어", "correct": "고친단어", "reason": "설명"}
  ]
}
문장: $text
""";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $groqApiKey'},
        body: jsonEncode({"model": "llama-3.3-70b-versatile", "messages": [{"role": "user", "content": prompt}]}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final result = jsonDecode(data['choices'][0]['message']['content']);
        setState(() {
          correctedText = result['corrected_text'];
          mistakes = List<Map<String, String>>.from(result['mistakes'].map((m) => Map<String, String>.from(m)));
          isResultMode = true;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() { correctedText = "오류 발생"; isLoading = false; });
    }
  }

  // 🔍 OCR 및 카메라
  Future<void> _takePicture() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() { isLoading = true; isResultMode = false; isEditing = false; });
      final inputImage = InputImage.fromFilePath(image.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText result = await textRecognizer.processImage(inputImage);
      setState(() { _textController.text = result.text; isEditing = true; isLoading = false; });
      textRecognizer.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6E0F8),
      appBar: AppBar(
        backgroundColor: Colors.purple[100],
        title: const Text('Write Buddy', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
                    ),
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : isEditing ? _buildEditView() : isResultMode ? _buildResultView() : _buildInitialView(),
                  ),
                  // ✨ 결과창이 하단바에 가리지 않도록 넉넉한 여백 추가
                  if (isResultMode) const SizedBox(height: 120),
                ],
              ),
            ),
          ),
          // 하단 버튼 구역 (내비게이션 바 위로 올림)
          if (isResultMode) _buildBottomIcons(),
          if (!isEditing && !isResultMode) _buildBottomMenu(),
        ],
      ),
    );
  }

  Widget _buildInitialView() {
    return Column(
      children: [
        const SizedBox(height: 50),
        Icon(Icons.auto_awesome, size: 60, color: Colors.purple[200]),
        const SizedBox(height: 20),
        const Text("사진을 촬영하여\n첨삭을 시작해보세요!", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEditView() {
    return Column(
      children: [
        const Text("추출된 문장을 확인하세요 ✏️", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
        const SizedBox(height: 20),
        TextField(controller: _textController, maxLines: null, decoration: const InputDecoration(border: OutlineInputBorder())),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => getAiFeedback(_textController.text),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
          child: const Text("AI 첨삭 받기 ✅"),
        ),
      ],
    );
  }

  Widget _buildResultView() {
    List<InlineSpan> spans = [];
    String textToProcess = correctedText;

    for (var m in mistakes) {
      String correctValue = m['correct']!;
      int index = textToProcess.indexOf(correctValue);

      if (index != -1) {
        if (index > 0) {
          spans.add(TextSpan(text: textToProcess.substring(0, index), style: const TextStyle(color: Colors.black, fontSize: 18)));
        }
        spans.add(
          TextSpan(
            text: correctValue,
            style: const TextStyle(
              color: Colors.red,
              decoration: TextDecoration.underline,
              decorationColor: Colors.red,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _showReason(m['wrong']!, m['correct']!, m['reason']!),
          ),
        );
        textToProcess = textToProcess.substring(index + correctValue.length);
      }
    }
    if (textToProcess.isNotEmpty) {
      spans.add(TextSpan(text: textToProcess, style: const TextStyle(color: Colors.black, fontSize: 18)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(text: TextSpan(children: spans)),
        const Divider(height: 40, thickness: 1.5),
        const Text("MISTAKES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
        const SizedBox(height: 10),
        ...mistakes.map((m) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text("- ${m['wrong']} -> ${m['correct']}", style: const TextStyle(fontSize: 15)),
        )).toList(),
      ],
    );
  }

  void _showReason(String w, String c, String r) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("$w -> $c"), content: Text(r), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
  }

  // ✨ 카메라 버튼 위치를 위로 올림
  Widget _buildBottomMenu() {
    return Padding(
        padding: const EdgeInsets.only(bottom: 80), // 💡 40에서 80으로 높임
        child: GestureDetector(
            onTap: _takePicture,
            child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, size: 40, color: Colors.white)
            )
        )
    );
  }

  // ✨ 결과창 아이콘 바 위치를 위로 올림
  Widget _buildBottomIcons() {
    return Container(
      padding: const EdgeInsets.only(top: 15, bottom: 60), // 💡 바닥 여백을 60으로 늘림
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _iconItem(Icons.search, "정답", () {}),
          _iconItem(Icons.edit_note, "저장", () {}),
          _iconItem(Icons.refresh, "다시", () => setState(() => isResultMode = false)),
        ],
      ),
    );
  }

  Widget _iconItem(IconData i, String l, VoidCallback o) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: Icon(i, color: Colors.purple, size: 30), onPressed: o),
        Text(l, style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold))
      ]
  );
}