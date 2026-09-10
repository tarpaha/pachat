import 'dart:async';
import 'package:flutter/material.dart';
import '../services/profile_storage.dart';
import 'login_screen.dart';

class DeviceProfileScreen extends StatefulWidget {
  final ProfileCatalog? catalog;
  const DeviceProfileScreen({super.key, this.catalog});

  @override
  State<DeviceProfileScreen> createState() => _DeviceProfileScreenState();
}

class _DeviceProfileScreenState extends State<DeviceProfileScreen> {
  LocalProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final catalog = widget.catalog ?? await ProfileCatalog.device();
      final profile = await catalog.openDeviceProfile();
      if (!mounted) {
        await profile.close();
        return;
      }
      setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load saved data: $e');
    }
  }

  @override
  void dispose() {
    final profile = _profile;
    if (profile != null) unawaited(profile.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile != null) return LoginScreen(profile: profile, showProfileName: false);
    return Scaffold(
      appBar: AppBar(title: const Text('PaChat')),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
      ),
    );
  }
}
