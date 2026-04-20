import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: FlashlightScreen(),
    );
  }
}

class FlashlightScreen extends StatefulWidget {
  const FlashlightScreen({super.key});

  @override
  State<FlashlightScreen> createState() => _FlashlightScreenState();
}

class _FlashlightScreenState extends State<FlashlightScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _vibrationChannel = MethodChannel(
    'torch_app/vibration',
  );
  static const MethodChannel _torchChannel = MethodChannel('torch_app/torch');
  static const MethodChannel _batteryChannel = MethodChannel(
    'torch_app/battery',
  );
  static const MethodChannel _voiceChannel = MethodChannel('torch_app/voice');

  bool isOn = false;
  bool isVoiceListening = false;
  double brightness = 1;
  int? batteryPercent;

  int get brightnessPercent => (brightness * 100).round();
  String get batteryText => batteryPercent == null ? "--%" : "$batteryPercent%";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceChannel.setMethodCallHandler(handleVoiceCall);
    loadBatteryPercent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceChannel.setMethodCallHandler(null);
    _voiceChannel.invokeMethod<void>('stopListening');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadBatteryPercent();
    }
  }

  Future<void> loadBatteryPercent() async {
    try {
      final value = await _batteryChannel.invokeMethod<int>('getBatteryPercent');
      if (!mounted) {
        return;
      }

      setState(() {
        batteryPercent = value;
      });
    } on PlatformException catch (e) {
      debugPrint("Battery error: ${e.message}");
    } on MissingPluginException catch (e) {
      debugPrint("Battery plugin missing: ${e.message}");
    }
  }

  Future<void> handleVoiceCall(MethodCall call) async {
    if (call.method != 'voiceCommand') {
      return;
    }

    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final command = arguments['command'] as String?;

    try {
      if (command == 'on' && !isOn) {
        await setTorchOn();
        if (!mounted) {
          return;
        }
        setState(() {
          isOn = true;
        });
      } else if (command == 'off' && isOn) {
        await setTorchOff();
        if (!mounted) {
          return;
        }
        setState(() {
          isOn = false;
        });
      }
    } catch (e) {
      debugPrint("Voice command error: $e");
    }
  }

  Future<void> toggleVoiceActivation() async {
    try {
      if (isVoiceListening) {
        await _voiceChannel.invokeMethod<void>('stopListening');
      } else {
        await _voiceChannel.invokeMethod<void>('startListening');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        isVoiceListening = !isVoiceListening;
      });
    } on PlatformException catch (e) {
      debugPrint("Voice activation error: ${e.message}");
    } on MissingPluginException catch (e) {
      debugPrint("Voice plugin missing: ${e.message}");
    }
  }

  Future<void> vibrateOnTap() async {
    try {
      await _vibrationChannel.invokeMethod<void>('click');
    } on PlatformException catch (e) {
      debugPrint("Vibration error: ${e.message}");
      HapticFeedback.mediumImpact();
    } on MissingPluginException catch (e) {
      debugPrint("Vibration plugin missing: ${e.message}");
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> setTorchOn() async {
    await _torchChannel.invokeMethod<void>('setBrightness', {
      'brightness': brightness,
    });
  }

  Future<void> setTorchOff() async {
    await _torchChannel.invokeMethod<void>('disable');
  }

  Future<void> toggleFlashlight() async {
    try {
      await vibrateOnTap();

      if (isOn) {
        await setTorchOff();
      } else {
        await setTorchOn();
      }

      setState(() {
        isOn = !isOn;
      });
    } catch (e) {
      debugPrint("Flashlight error: $e");
    }
  }

  Future<void> updateBrightness(double value) async {
    setState(() {
      brightness = value;
    });

    if (!isOn) {
      return;
    }

    try {
      await setTorchOn();
    } catch (e) {
      debugPrint("Brightness error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isOn ? Colors.white : const Color(0xFF080D10);
    final primaryTextColor = isOn ? const Color(0xFF101417) : Colors.white;
    final mutedTextColor = isOn ? Colors.black54 : Colors.white54;
    final accentColor = isOn
        ? const Color(0xFF009CA6)
        : const Color(0xFF8CFBFF);
    final panelColor = isOn ? Colors.white : const Color(0xFF11181C);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: isOn
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFE8FBFC),
                    ],
                  )
                : const RadialGradient(
                    center: Alignment(0, -0.1),
                    radius: 1.1,
                    colors: [
                      Color(0xFF1A252A),
                      Color(0xFF080D10),
                    ],
                  ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.flashlight_on_rounded,
                      size: 18,
                      color: mutedTextColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "LUMOS",
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: toggleVoiceActivation,
                      tooltip: "Voice activation",
                      icon: Icon(
                        isVoiceListening
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        color: isVoiceListening ? accentColor : mutedTextColor,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: panelColor.withOpacity(
                          isOn ? 0.7 : 0.95,
                        ),
                        fixedSize: const Size(44, 44),
                        shape: const CircleBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: toggleFlashlight,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: panelColor,
                    border: Border.all(color: accentColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(isOn ? 0.34 : 0.5),
                        blurRadius: isOn ? 32 : 42,
                        spreadRadius: isOn ? 3 : 8,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(isOn ? 0.08 : 0.55),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.power_settings_new_rounded,
                        size: 78,
                        color: accentColor,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isOn ? "TAP TO SLEEP" : "TAP TO ACTIVATE",
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 44),
              Text(
                "BRIGHTNESS",
                style: TextStyle(
                  color: mutedTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(-70, 0),
                      child: SizedBox(
                        width: 46,
                        height: 220,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "100%",
                              style: TextStyle(
                                color: mutedTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              "0%",
                              style: TextStyle(
                                color: mutedTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accentColor.withOpacity(0.18),
                            Colors.white.withOpacity(isOn ? 0.95 : 0.9),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.26),
                            blurRadius: 34,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 50,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: accentColor,
                          overlayColor: accentColor.withOpacity(0.14),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 18,
                            elevation: 0,
                            pressedElevation: 0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 26,
                          ),
                        ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: brightness,
                            min: 0,
                            max: 1,
                            divisions: 100,
                            onChanged: updateBrightness,
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(112, 0),
                      child: SizedBox(
                        width: 92,
                        child: Text(
                          "$brightnessPercent%",
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "BATTERY: ",
                          style: TextStyle(color: mutedTextColor),
                        ),
                        TextSpan(
                          text: batteryText,
                          style: TextStyle(color: primaryTextColor),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
