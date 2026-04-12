import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:fl_chart/fl_chart.dart';

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

  // Groq API Key
  static const String groqApiKey = "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";

  // AI 첨삭 로직 (한자 필터 및 모바일 최적화 프롬프트)
  Future<void> getAiFeedback(String text) async {
    setState(() { isLoading = true; isEditing = false; });
    const String url = "https://api.groq.com/openai/v1/chat/completions";

    const String systemPrompt = """
당신은 학생의 영어를 친절하게 고쳐주는 다정한 선생님 'Write Buddy'입니다.

[🚨 콩글리시 판별 가이드 🚨]
- 한국어식 표현을 그대로 영어 단어로 옮긴 것들(예: eye shopping, service bread, hand phone, skinship 등)은 무조건 **[분류: 콩글리시]**로 정의하세요.
- 단순히 단어를 틀린 게 아니라, 한국에서만 쓰는 잘못된 영어 표현이라면 반드시 콩글리시로 분류해야 합니다.

[🚨 절대 엄수 규칙 🚨]
1. 모든 설명(reason)은 **순수 한글**로만 작성하세요. 한자(漢字)는 절대 금지입니다.
2. 말투는 "~해요", "~네요" 처럼 학생에게 말하듯 **아주 상냥하게** 작성하세요.
3. 2. 모든 설명(reason)의 **맨 앞**에 반드시 [분류: 콩글리시], [분류: 문법], [분류: 어휘] 중 하나를 먼저 쓰고 설명을 시작하세요.
4. 설명 형식: "이 문장에서 [영어단어]는 ~라는 뜻이에요. 여기서는 ~해서 어색해요. 대신 [고친단어]를 쓰면 돼요!"
5. 반드시 아래 JSON 형식으로만 답하세요. (JSON 외의 텍스트는 금지)
 
{
  "corrected_text": "교정된 영어 문장",
  "mistakes": [
    { "wrong": "틀린부분", "correct": "고친부분", "reason": "상냥한 한글 설명" }
  ]
}
""";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $groqApiKey',
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {"role": "system", "content": systemPrompt},
            {"role": "user", "content": text}
          ],
          "response_format": {"type": "json_object"}
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        String responseBody = utf8.decode(response.bodyBytes);
        // 🛡️ 혹시 모를 한자 강제 필터링
        responseBody = responseBody.replaceAll(RegExp(r'[\u4e00-\u9fa5]'), '');

        final data = jsonDecode(responseBody);
        final result = jsonDecode(data['choices'][0]['message']['content']);

        setState(() {
          correctedText = result['corrected_text'] ?? "";
          mistakes = List<Map<String, String>>.from(
              (result['mistakes'] as List).map((m) => Map<String, String>.from(m))
          );
          isResultMode = true;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() { isLoading = false; isEditing = true; });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("선생님이 문장을 읽다가 잠시 깜빡 졸았나 봐요! 다시 시도해 주세요.")));
    }
  }

  // 분석 리포트 (차트 기능)
  void _showAnalysis() {
    double konglish = 0, grammar = 0, vocab = 0;
    for (var m in mistakes) {
      String r = m['reason'] ?? "";
      // 🔍 키워드를 대폭 늘려서 '기타'나 '어휘'로 쏠리는 걸 방지해요!
      if (r.contains('콩글리시') || r.contains('한국식') || r.contains('직역') || r.contains('그대로 옮')) {
        konglish++;
      } else if (r.contains('문법') || r.contains('동사') || r.contains('시제') || r.contains('관사') || r.contains('어순') || r.contains('틀려요')) {
        grammar++;
      } else {
        // 어휘, 표현, 단어 선택 등은 모두 이쪽으로!
        vocab++;
      }
    }

    // ✅ 수치 계산 로직
    double total = konglish + grammar + vocab;
    String kPct = total == 0 ? "0" : ((konglish / total) * 100).toStringAsFixed(1);
    String gPct = total == 0 ? "0" : ((grammar / total) * 100).toStringAsFixed(1);
    String vPct = total == 0 ? "0" : ((vocab / total) * 100).toStringAsFixed(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        height: MediaQuery.of(context).size.height * 0.75, // 퍼센트 표시를 위해 높이를 살짝 키웠어요!
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            const Text("나의 취약점 분석 리포트 📊", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            Expanded(
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(value: (total == 0) ? 1 : konglish, title: total == 0 ? '' : '콩글', color: Colors.purple[300]!, radius: 60, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(value: grammar, title: total == 0 ? '' : '문법', color: Colors.blue[300]!, radius: 60, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(value: vocab, title: total == 0 ? '' : '어휘', color: Colors.orange[300]!, radius: 60, titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              )),
            ),
            const SizedBox(height: 20),

            // ✅ 퍼센트(%) 수치 표시 박스
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  _analysisRow("👾 콩글리시 비중", "$kPct%", Colors.purple),
                  const SizedBox(height: 12),
                  _analysisRow("📝 문법 오류 비중", "$gPct%", Colors.blue),
                  const SizedBox(height: 12),
                  _analysisRow("📚 어휘 개선 필요", "$vPct%", Colors.orange),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Text(
              "💡 ${total == 0 ? '완벽한 문장이에요!' : konglish >= grammar && konglish >= vocab ? '한국식 표현을 원어민 스타일로 바꿔보세요!' : '문법과 어휘를 조금 더 다듬으면 완벽해요!'}",
              style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 수치 표시를 도와주는 작은 위젯 (이것도 _showAnalysis 바로 아래에 넣어주세요!)
  Widget _analysisRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // 이미지 처리 (카메라/갤러리)
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image == null) return;

    setState(() { isLoading = true; isResultMode = false; });

    final inputImage = InputImage.fromFilePath(image.path);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText result = await textRecognizer.processImage(inputImage);

    setState(() {
      _textController.text = result.text;
      isEditing = true;
      isLoading = false;
    });
    textRecognizer.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Write Buddy', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 24)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: isLoading
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 20), Text("선생님이 문장을 검토 중이에요...")] ))
                    : isEditing ? _buildEditView() : isResultMode ? _buildResultView() : _buildInitialView(),
              ),
            ),
          ),
          if (isResultMode) _buildResultMenu(),
          if (!isEditing && !isResultMode) _buildMainMenu(),
        ],
      ),
    );
  }

  Widget _buildInitialView() => Column(children: [const SizedBox(height: 50), Icon(Icons.auto_awesome_rounded, size: 80, color: Colors.purple[100]), const SizedBox(height: 25), const Text("영어 일기나 문장을\n사진으로 찍어보세요!", textAlign: TextAlign.center, style: TextStyle(fontSize: 19, color: Colors.black54, height: 1.5))]);

  Widget _buildEditView() => Column(children: [
    const Text("문장에 틀린 글자가 있나요? ✏️", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 17)),
    const SizedBox(height: 20),
    TextField(controller: _textController, maxLines: null, decoration: InputDecoration(filled: true, fillColor: Colors.grey[50], border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))),
    const SizedBox(height: 20),
    ElevatedButton(
      onPressed: () => getAiFeedback(_textController.text),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      child: const Text("선생님께 첨삭 받기 ✅", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
    )
  ]);

  Widget _buildResultView() {
    List<InlineSpan> spans = [];
    String textToProcess = correctedText;
    for (var m in mistakes) {
      String correctValue = m['correct']!;
      int index = textToProcess.indexOf(correctValue);
      if (index != -1) {
        if (index > 0) spans.add(TextSpan(text: textToProcess.substring(0, index), style: const TextStyle(color: Colors.black87, fontSize: 20)));
        spans.add(TextSpan(
            text: correctValue,
            style: const TextStyle(color: Colors.deepOrange, decoration: TextDecoration.underline, fontSize: 20, fontWeight: FontWeight.bold),
            recognizer: TapGestureRecognizer()..onTap = () => _showReason(m['wrong']!, m['correct']!, m['reason']!)
        ));
        textToProcess = textToProcess.substring(index + correctValue.length);
      }
    }
    if (textToProcess.isNotEmpty) spans.add(TextSpan(text: textToProcess, style: const TextStyle(color: Colors.black87, fontSize: 20)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(text: TextSpan(children: spans)),
      const Padding(padding: EdgeInsets.symmetric(vertical: 25), child: Divider(thickness: 1, color: Color(0xFFEEEEEE))),

      // ✅ 여기서부터 단어 수정 목록입니다!
      const Text("고친 부분들 ✨", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 17)),
      const SizedBox(height: 15),
      ...mistakes.map((m) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    "${m['wrong']}  →  ${m['correct']}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)
                ),
              ),
            ],
          ),
        ),
      )).toList(),
      const SizedBox(height: 20),
      const Text("💡 단어를 터치하면 선생님의 꿀팁이 나와요!", style: TextStyle(color: Colors.grey, fontSize: 13)),
    ]);
  }

  void _showReason(String w, String c, String r) => showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: Text("$w → $c", style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
      content: Text(r, style: const TextStyle(height: 1.6)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("알겠어요!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))]
  ));

  Widget _buildMainMenu() => Padding(padding: const EdgeInsets.only(bottom: 60), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionButton(Icons.camera_alt_rounded, "카메라", () => _pickImage(ImageSource.camera), true),
    const SizedBox(width: 30),
    _actionButton(Icons.image_search_rounded, "갤러리", () => _pickImage(ImageSource.gallery), false),
  ]));

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, bool primary) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: primary ? Colors.purple : Colors.white, shape: BoxShape.circle, border: primary ? null : Border.all(color: Colors.purple, width: 2), boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]), child: Icon(icon, color: primary ? Colors.white : Colors.purple, size: 32)),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 13))
    ]),
  );

  Widget _buildResultMenu() => Container(padding: const EdgeInsets.only(top: 20, bottom: 50), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _iconItem(Icons.analytics_rounded, "분석 리포트", _showAnalysis),
    _iconItem(Icons.restart_alt_rounded, "다시 찍기", () => setState(() => isResultMode = false)),
  ]));

  Widget _iconItem(IconData i, String l, VoidCallback o) => Column(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: Icon(i, color: Colors.purple, size: 32), onPressed: o), Text(l, style: const TextStyle(color: Colors.purple, fontSize: 13, fontWeight: FontWeight.bold))]);
}

