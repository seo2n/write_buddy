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

  static const String groqApiKey = "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";

  // ✅ AI 첨삭 함수 (번역 방지 및 상세 설명 강화)
  Future<void> getAiFeedback(String text) async {
    setState(() { isLoading = true; isEditing = false; });
    const String url = "https://api.groq.com/openai/v1/chat/completions";
    const String systemPrompt = """
당신은 한국인 학생을 위한 전문 영어 첨삭 튜터 'Write Buddy'입니다. 

[중요 지시 사항 - 반드시 한글로만 대답하세요]
1. 모든 설명(reason)은 **오직 표준 한국어(Pure Modern Korean)**로만 작성하세요. 
2. **일본어, 한자, 러시아어, 특수 기호**를 절대 섞지 마세요. (예: '看', 'って' 같은 글자 사용 금지)
3. 설명은 3~4문장으로 매우 친절하고 상냥하게 작성하세요.
4. 교정된 문장(corrected_text)은 반드시 **영어(English)**로만 출력하세요.

반드시 아래 JSON 형식으로만 답하세요:
{
  "corrected_text": "교정된 영어 문장",
  "mistakes": [
    {
      "wrong": "틀린 영어", 
      "correct": "고친 영어", 
      "reason": "오직 한국어(한글)로만 작성된 상세 설명"
    }
  ]
}
""";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $groqApiKey'},
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [{"role": "system", "content": systemPrompt}, {"role": "user", "content": text}],
          "response_format": {"type": "json_object"}
        }),
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
      setState(() { isLoading = false; });
    }
  }

  // --- 분석 화면 (PieChart + BarChart) ---
  void _showAnalysis() {
    double konglish = 0, grammar = 0, vocab = 0, spelling = 0;
    for (var m in mistakes) {
      if (m['reason']!.contains('콩글리시')) konglish++;
      else if (m['reason']!.contains('문법')) grammar++;
      else if (m['reason']!.contains('어휘')) vocab++;
      else spelling++;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 15),
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("취약점 분석 리포트 📊", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Text("오류 항목별 비중", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: PieChart(PieChartData(
                        sections: [
                          PieChartSectionData(value: (konglish+grammar+vocab+spelling == 0) ? 1 : konglish, title: '콩글리시', color: Colors.purple, radius: 50, showTitle: true),
                          PieChartSectionData(value: grammar, title: '문법', color: Colors.blue, radius: 50, showTitle: true),
                          PieChartSectionData(value: vocab, title: '어휘', color: Colors.orange, radius: 50, showTitle: true),
                          PieChartSectionData(value: spelling, title: '기타', color: Colors.grey, radius: 50, showTitle: true),
                        ],
                      )),
                    ),
                    const SizedBox(height: 40),
                    const Text("항목별 오류 개수 비교", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 30),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          maxY: 10,
                          barGroups: [
                            BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: konglish, color: Colors.purple, width: 20)]),
                            BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: grammar, color: Colors.blue, width: 20)]),
                            BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: vocab, color: Colors.orange, width: 20)]),
                            BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: spelling, color: Colors.grey, width: 20)]),
                          ],
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  switch (value.toInt()) {
                                    case 0: return const Text('콩글');
                                    case 1: return const Text('문법');
                                    case 2: return const Text('어휘');
                                    case 3: return const Text('기타');
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(15)),
                      child: Text("💡 분석 결과: 현재 콩글리시($konglish건) 사용 빈도가 높습니다. 원어민 관용구를 익히는 데 집중하면 더 자연스러운 영어가 될 거예요!",
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📷 카메라 촬영
  Future<void> _takePicture() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) _processPickedImage(image);
  }

  // 🖼️ 갤러리 불러오기
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) _processPickedImage(image);
  }

  // 공통 이미지 처리 로직
  Future<void> _processPickedImage(XFile image) async {
    setState(() { isLoading = true; isResultMode = false; isEditing = false; });
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
      backgroundColor: const Color(0xFFE6E0F8),
      appBar: AppBar(backgroundColor: Colors.purple[100], title: const Text('Write Buddy', style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)]),
              child: isLoading ? const Center(child: CircularProgressIndicator()) : isEditing ? _buildEditView() : isResultMode ? _buildResultView() : _buildInitialView(),
            ),
          )),
          if (isResultMode) _buildBottomIcons(),
          if (!isEditing && !isResultMode) _buildBottomMenu(),
        ],
      ),
    );
  }

  Widget _buildInitialView() => Column(children: [const SizedBox(height: 50), Icon(Icons.auto_awesome, size: 60, color: Colors.purple[200]), const SizedBox(height: 20), const Text("사진을 촬영하거나 불러와서\n첨삭을 시작해보세요!", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.grey))]);

  Widget _buildEditView() => Column(children: [const Text("추출된 문장을 확인하세요 ✏️", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)), const SizedBox(height: 20), TextField(controller: _textController, maxLines: null, decoration: const InputDecoration(border: OutlineInputBorder())), const SizedBox(height: 20), ElevatedButton(onPressed: () => getAiFeedback(_textController.text), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), child: const Text("AI 첨삭 받기 ✅"))]);

  Widget _buildResultView() {
    List<InlineSpan> spans = [];
    String textToProcess = correctedText;
    for (var m in mistakes) {
      String correctValue = m['correct']!;
      int index = textToProcess.indexOf(correctValue);
      if (index != -1) {
        if (index > 0) spans.add(TextSpan(text: textToProcess.substring(0, index), style: const TextStyle(color: Colors.black, fontSize: 18)));
        spans.add(TextSpan(text: correctValue, style: const TextStyle(color: Colors.red, decoration: TextDecoration.underline, fontSize: 18, fontWeight: FontWeight.bold), recognizer: TapGestureRecognizer()..onTap = () => _showReason(m['wrong']!, m['correct']!, m['reason']!)));
        textToProcess = textToProcess.substring(index + correctValue.length);
      }
    }
    if (textToProcess.isNotEmpty) spans.add(TextSpan(text: textToProcess, style: const TextStyle(color: Colors.black, fontSize: 18)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RichText(text: TextSpan(children: spans)), const Divider(height: 40, thickness: 1.5), const Text("MISTAKES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)), const SizedBox(height: 10), ...mistakes.map((m) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text("- ${m['wrong']} -> ${m['correct']}", style: const TextStyle(fontSize: 15)))).toList()]);
  }

  void _showReason(String w, String c, String r) => showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("$w -> $c"), content: Text(r), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));

  // ✅ 하단 메뉴: 카메라 + 갤러리 두 개 버튼으로 수정
  Widget _buildBottomMenu() => Padding(
    padding: const EdgeInsets.only(bottom: 80),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(onTap: _takePicture, child: Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 35, color: Colors.white))),
        const SizedBox(width: 30),
        GestureDetector(onTap: _pickFromGallery, child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.purple, width: 2)), child: const Icon(Icons.photo_library, size: 35, color: Colors.purple))),
      ],
    ),
  );

  Widget _buildBottomIcons() => Container(
    padding: const EdgeInsets.only(top: 15, bottom: 60), color: Colors.white,
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _iconItem(Icons.search, "분석", _showAnalysis),
      _iconItem(Icons.edit_note, "저장", () {}),
      _iconItem(Icons.refresh, "다시", () => setState(() => isResultMode = false)),
    ]),
  );

  Widget _iconItem(IconData i, String l, VoidCallback o) => Column(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: Icon(i, color: Colors.purple, size: 30), onPressed: o), Text(l, style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold))]);
}