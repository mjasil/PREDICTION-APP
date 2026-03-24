import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String kBaseUrl = 'https://your-api-server.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PredictionApp());
}

class PeriodInfo {
  final String periodNumber;
  final int remainingSeconds;
  final bool isRunning;
  PeriodInfo({required this.periodNumber, required this.remainingSeconds, required this.isRunning});
  factory PeriodInfo.fromJson(Map<String, dynamic> json) => PeriodInfo(
    periodNumber: json['period']?.toString() ?? '0000',
    remainingSeconds: json['remaining_seconds'] ?? 0,
    isRunning: json['is_running'] ?? false,
  );
}

class PredictionResult {
  final String periodNumber;
  final int number;
  final String color;
  final String size;
  PredictionResult({required this.periodNumber, required this.number, required this.color, required this.size});
  factory PredictionResult.fromJson(Map<String, dynamic> json) => PredictionResult(
    periodNumber: json['period']?.toString() ?? '',
    number: json['number'] ?? 0,
    color: (json['color'] ?? 'GREEN').toString().toUpperCase(),
    size: (json['size'] ?? 'SMALL').toString().toUpperCase(),
  );
}

class ApiService {
  static Future<PeriodInfo> fetchCurrentPeriod() async {
    final res = await http.get(Uri.parse('$kBaseUrl/current-period')).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return PeriodInfo.fromJson(jsonDecode(res.body));
    throw Exception('Failed: ${res.statusCode}');
  }
  static Future<List<PredictionResult>> fetchHistory() async {
    final res = await http.get(Uri.parse('$kBaseUrl/history')).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => PredictionResult.fromJson(e)).toList();
    }
    throw Exception('Failed: ${res.statusCode}');
  }
}

class PredictionApp extends StatelessWidget {
  const PredictionApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prediction System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const PredictionScreen(),
    );
  }
}

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});
  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> with TickerProviderStateMixin {
  PeriodInfo? _period;
  PredictionResult? _result;
  List<PredictionResult> _history = [];
  bool _showResult = false;
  bool _isLoading = false;
  bool _isFetching = false;
  String? _errorMsg;
  Timer? _countdownTimer;
  Timer? _pollingTimer;
  int _remainingSeconds = 0;

  late AnimationController _resultController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnim;

  @override
  void initState() {
    super.initState();
    _resultController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _resultController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _resultController, curve: Curves.elasticOut),
    );
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _buttonController = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _buttonScaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );
    _loadPeriod();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadPeriod(silent: true));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _resultController.dispose();
    _pulseController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  Future<void> _loadPeriod({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final period = await ApiService.fetchCurrentPeriod();
      if (mounted) {
        setState(() {
          _period = period;
          _remainingSeconds = period.remainingSeconds;
          _isLoading = false;
          _errorMsg = null;
        });
        _startCountdown();
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() { _isLoading = false; _errorMsg = 'Unable to reach server'; });
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_remainingSeconds > 0) { _remainingSeconds--; } else { t.cancel(); }
      });
    });
  }

  Future<void> _onNextPrediction() async {
    await _buttonController.forward();
    await _buttonController.reverse();
    if (_isFetching) return;
    setState(() { _isFetching = true; _showResult = false; _errorMsg = null; });
    _resultController.reset();
    try {
      final period = await ApiService.fetchCurrentPeriod();
      final historyList = await ApiService.fetchHistory();
      PredictionResult? result;
      if (historyList.isNotEmpty) result = historyList.first;
      if (mounted) {
        setState(() {
          _period = period;
          _remainingSeconds = period.remainingSeconds;
          _history = historyList.take(10).toList();
          _result = result;
          _showResult = result != null;
          _isFetching = false;
        });
        _startCountdown();
        if (_showResult) _resultController.forward();
      }
    } catch (e) {
      if (mounted) setState(() { _isFetching = false; _errorMsg = 'Failed to fetch prediction'; });
    }
  }

  String get _formattedTimer {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _resultColor {
    if (_result == null) return Colors.white;
    return _result!.color == 'RED' ? const Color(0xFFFF3B5C) : const Color(0xFF00FF99);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _BackgroundImage(),
          _BlurOverlay(),
          SafeArea(
            child: _isLoading
                ? const Center(child: _LoadingWidget())
                : Column(
                    children: [
                      _TopBar(period: _period),
                      const SizedBox(height: 12),
                      _TimerWidget(timer: _formattedTimer, pulse: _pulseAnim, remaining: _remainingSeconds),
                      const Spacer(),
                      if (_showResult && _result != null)
                        _ResultCard(result: _result!, fadeAnim: _fadeAnim, scaleAnim: _scaleAnim, accentColor: _resultColor),
                      const Spacer(),
                      _NextButton(onTap: _onNextPrediction, isLoading: _isFetching, scaleAnim: _buttonScaleAnim),
                      const SizedBox(height: 28),
                      if (_errorMsg != null) _ErrorBanner(msg: _errorMsg!),
                      if (_history.isNotEmpty) _HistorySection(history: _history),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/bg.jpg',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A1A), Color(0xFF0D1B2A), Color(0xFF050510)],
          ),
        ),
      ),
    );
  }
}

class _BlurOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.55),
              Colors.black.withOpacity(0.75),
              Colors.black.withOpacity(0.90),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 48, height: 48,
          child: CircularProgressIndicator(color: const Color(0xFF00FFB2), strokeWidth: 2.5),
        ),
        const SizedBox(height: 16),
        Text('CONNECTING...', style: TextStyle(color: Colors.white.withOpacity(0.5), letterSpacing: 4, fontSize: 12)),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final PeriodInfo? period;
  const _TopBar({this.period});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PREDICT', style: TextStyle(color: const Color(0xFF00FFB2), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 6)),
              Text('SYSTEM', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, letterSpacing: 8)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFB2).withOpacity(0.35), width: 1),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF00FFB2).withOpacity(0.06),
            ),
            child: Column(
              children: [
                Text('PERIOD', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8, letterSpacing: 3)),
                const SizedBox(height: 2),
                Text(period?.periodNumber ?? '─────',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  final String timer;
  final Animation<double> pulse;
  final int remaining;
  const _TimerWidget({required this.timer, required this.pulse, required this.remaining});
  @override
  Widget build(BuildContext context) {
    final isUrgent = remaining <= 10 && remaining > 0;
    final color = isUrgent ? const Color(0xFFFF3B5C) : const Color(0xFF00FFB2);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Transform.scale(scale: isUrgent ? pulse.value : 1.0, child: child),
      child: Column(
        children: [
          Text('NEXT DRAW IN', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10, letterSpacing: 5)),
          const SizedBox(height: 8),
          Text(timer, style: TextStyle(color: color, fontSize: 58, fontWeight: FontWeight.w900, letterSpacing: 4,
            shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 20), Shadow(color: color.withOpacity(0.3), blurRadius: 40)])),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 120, height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, color.withOpacity(0.7), Colors.transparent]),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final PredictionResult result;
  final Animation<double> fadeAnim;
  final Animation<double> scaleAnim;
  final Color accentColor;
  const _ResultCard({required this.result, required this.fadeAnim, required this.scaleAnim, required this.accentColor});
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: ScaleTransition(
        scale: scaleAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [accentColor.withOpacity(0.12), Colors.black.withOpacity(0.6), accentColor.withOpacity(0.06)],
            ),
            boxShadow: [BoxShadow(color: accentColor.withOpacity(0.25), blurRadius: 40, spreadRadius: 2)],
          ),
          child: Column(
            children: [
              Text(result.number.toString(), style: TextStyle(color: Colors.white, fontSize: 96,
                fontWeight: FontWeight.w900, height: 0.9,
                shadows: [Shadow(color: accentColor.withOpacity(0.8), blurRadius: 30), Shadow(color: accentColor.withOpacity(0.4), blurRadius: 60)])),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Badge(label: result.color, color: result.color == 'RED' ? const Color(0xFFFF3B5C) : const Color(0xFF00FF99), icon: result.color == 'RED' ? '🔴' : '🟢'),
                  const SizedBox(width: 12),
                  _Badge(label: result.size, color: const Color(0xFF7B61FF), icon: result.size == 'BIG' ? '⬆' : '⬇'),
                ],
              ),
              const SizedBox(height: 16),
              Text('PERIOD  ${result.periodNumber}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final String icon;
  const _Badge({required this.label, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 2)),
        ],
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isLoading;
  final Animation<double> scaleAnim;
  const _NextButton({required this.onTap, required this.isLoading, required this.scaleAnim});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scaleAnim,
      builder: (_, child) => Transform.scale(scale: scaleAnim.value, child: child),
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [Color(0xFF00FFB2), Color(0xFF00C896)]),
            boxShadow: [BoxShadow(color: const Color(0xFF00FFB2).withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                : const Text('NEXT PREDICTION', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 3)),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String msg;
  const _ErrorBanner({required this.msg});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B5C).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF3B5C).withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B5C), size: 16),
          const SizedBox(width: 8),
          Text(msg, style: const TextStyle(color: Color(0xFFFF3B5C), fontSize: 12, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final List<PredictionResult> history;
  const _HistorySection({required this.history});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(color: const Color(0xFF00FFB2), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('LAST 10 RESULTS', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, letterSpacing: 4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: history.length,
            itemBuilder: (_, i) => _HistoryItem(result: history[i], isLatest: i == 0),
          ),
        ),
      ],
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final PredictionResult result;
  final bool isLatest;
  const _HistoryItem({required this.result, required this.isLatest});
  @override
  Widget build(BuildContext context) {
    final isRed = result.color == 'RED';
    final color = isRed ? const Color(0xFFFF3B5C) : const Color(0xFF00FF99);
    return Container(
      width: 54,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(isLatest ? 0.2 : 0.08),
        border: Border.all(color: color.withOpacity(isLatest ? 0.6 : 0.25), width: isLatest ? 1.5 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(result.number.toString(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(result.size[0], style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
