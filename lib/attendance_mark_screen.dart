import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceMarkScreen extends StatefulWidget {
  final String username;
  final String role;

  const AttendanceMarkScreen({
    super.key,
    required this.username,
    required this.role,
  });

  @override
  State<AttendanceMarkScreen> createState() => _AttendanceMarkScreenState();
}

class _AttendanceMarkScreenState extends State<AttendanceMarkScreen> {
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbzHCmkMg-_e-GflpKI28XNQ0b7ECmq9TucAfnbVp1R6UhQLo7WYAsmCTTRsY06q2GbRxw/exec';

  static const String offlineQueueKey = 'offline_attendance';

  final TextEditingController _empCodeController = TextEditingController();

  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 1200,
  );

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String _name = '';
  String _company = '';

  bool _isLoading = false;
  bool _isScanning = true;
  bool _hasInternet = true;

  String _selectedStatus = 'Present';

  DateTime _selectedDate = DateTime.now();

  final List<String> _statuses = [
    'Present',
    'Absent',
    'Week Off',
    'Idle',
    'Sick',
    'Duty Return',
    'Duty Stop',
    'Cash',
  ];

  bool get _isAdmin => widget.role.trim().toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();

    _checkInternet();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        final online = !results.contains(ConnectivityResult.none);

        if (!mounted) return;

        setState(() {
          _hasInternet = online;
        });

        if (online) {
          _syncOfflineAttendance();
        }
      },
    );

    _syncOfflineAttendance();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _scannerController.dispose();
    _empCodeController.dispose();
    super.dispose();
  }

  Future<void> _checkInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();

      if (!mounted) return;

      setState(() {
        _hasInternet = !result.contains(ConnectivityResult.none);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _hasInternet = false;
      });
    }
  }

  String _dateString(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _selectDate() async {
    if (!_isAdmin) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _selectedDate = picked;
    });
  }

  Future<Map<String, dynamic>?> _fetchEmployee(
    String empCode,
  ) async {
    try {
      final uri = Uri.parse(
        '$scriptUrl'
        '?action=getEmployee'
        '&empCode=${Uri.encodeComponent(empCode)}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final body = response.body.trim();

      if (body.isEmpty) return null;

      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        return null;
      }

      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleQrScan(String value) async {
    if (!_isScanning) return;

    final code = value.trim();

    if (code.isEmpty) return;

    setState(() {
      _isScanning = false;
      _empCodeController.text = code;
    });

    await _fetchEmployeeDirectly(code);
  }

  Future<void> _fetchEmployeeDirectly(String code) async {
    final empCode = code.trim().toUpperCase();

    if (empCode.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _name = '';
      _company = '';
    });

    final online = await _checkActualInternet();

    if (!online) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isScanning = true;
      });

      _showMessage(
        'No internet connection.',
        Colors.red,
      );

      return;
    }

    final data = await _fetchEmployee(empCode);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isScanning = true;
    });

    if (data == null || data['success'] != true) {
      _showMessage(
        'Employee not found.',
        Colors.red,
      );
      return;
    }

    setState(() {
      _name = data['name']?.toString() ?? '';
      _company = data['company']?.toString() ?? '';
    });
  }

  Future<bool> _checkActualInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();

      final online = !result.contains(ConnectivityResult.none);

      if (mounted) {
        setState(() {
          _hasInternet = online;
        });
      }

      return online;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submitAttendance() async {
    final empCode = _empCodeController.text.trim().toUpperCase();

    if (empCode.isEmpty) {
      _showMessage(
        'Please scan QR or enter EMP Code.',
        Colors.orange,
      );
      return;
    }

    if (_name.isEmpty) {
      await _fetchEmployeeDirectly(empCode);

      if (_name.isEmpty) {
        return;
      }
    }

    final date = _dateString(_selectedDate);

    final online = await _checkActualInternet();

    if (!online) {
      await _saveOffline(
        empCode,
        date,
        _selectedStatus,
      );

      _showMessage(
        'OFFLINE SAVED',
        Colors.orange,
      );

      _clearAfterSave();

      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse(
        '$scriptUrl'
        '?action=saveAttendance'
        '&empCode=${Uri.encodeComponent(empCode)}'
        '&date=${Uri.encodeComponent(date)}'
        '&status=${Uri.encodeComponent(_selectedStatus)}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = response.body.trim();

        final decoded = jsonDecode(body);

        if (decoded is Map && decoded['success'] == true) {
          _showMessage(
            'SAVED IN GOOGLE SHEET',
            Colors.green,
          );

          _clearAfterSave();
        } else {
          await _saveOffline(
            empCode,
            date,
            _selectedStatus,
          );

          _showMessage(
            'Saved Offline',
            Colors.orange,
          );

          _clearAfterSave();
        }
      } else {
        await _saveOffline(
          empCode,
          date,
          _selectedStatus,
        );

        _showMessage(
          'Network error. OFFLINE SAVED',
          Colors.orange,
        );

        _clearAfterSave();
      }
    } catch (_) {
      await _saveOffline(
        empCode,
        date,
        _selectedStatus,
      );

      if (mounted) {
        _showMessage(
          'Connection error. OFFLINE SAVED',
          Colors.orange,
        );

        _clearAfterSave();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveOffline(
    String empCode,
    String date,
    String status,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getStringList(offlineQueueKey) ?? [];

    final item = jsonEncode({
      'empCode': empCode,
      'date': date,
      'status': status,
    });

    existing.add(item);

    await prefs.setStringList(
      offlineQueueKey,
      existing,
    );
  }

  Future<void> _syncOfflineAttendance() async {
    final online = await _checkActualInternet();

    if (!online) return;

    final prefs = await SharedPreferences.getInstance();

    final queue = prefs.getStringList(offlineQueueKey) ?? [];

    if (queue.isEmpty) return;

    final remaining = <String>[];

    for (final item in queue) {
      try {
        final data = jsonDecode(item);

        final empCode = data['empCode'].toString();

        final date = data['date'].toString();

        final status = data['status'].toString();

        final uri = Uri.parse(
          '$scriptUrl'
          '?action=saveAttendance'
          '&empCode=${Uri.encodeComponent(empCode)}'
          '&date=${Uri.encodeComponent(date)}'
          '&status=${Uri.encodeComponent(status)}',
        );

        final response =
            await http.get(uri).timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          remaining.add(item);
          continue;
        }

        final body = response.body.trim();

        final decoded = jsonDecode(body);

        if (decoded is! Map || decoded['success'] != true) {
          remaining.add(item);
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(
      offlineQueueKey,
      remaining,
    );

    if (remaining.isEmpty && queue.isNotEmpty && mounted) {
      _showMessage(
        'Offline attendance synced.',
        Colors.green,
      );
    }
  }

  void _clearAfterSave() {
    if (!mounted) return;

    setState(() {
      _empCodeController.clear();
      _name = '';
      _company = '';
      _selectedStatus = 'Present';
      _isScanning = true;

      if (!_isAdmin) {
        _selectedDate = DateTime.now();
      }
    });
  }

  void _logout() {
    Navigator.of(context).pop();
  }

  void _showMessage(
    String message,
    Color color,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.role),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      // =====================================================
      // FIX:
      // Android default navigation bar will no longer cover
      // the SAVE ATTENDANCE button.
      // =====================================================
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24,
          ),
          child: Column(
            children: [
              _buildInternetStatus(),

              const SizedBox(height: 12),

              _buildScanner(),

              const SizedBox(height: 12),

              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isScanning = true;
                  });
                },
                icon: const Icon(
                  Icons.qr_code_scanner,
                ),
                label: const Text(
                  'Scan Again',
                ),
              ),

              const SizedBox(height: 8),

              _buildEmployeeInput(),

              const SizedBox(height: 16),

              _buildEmployeeCard(),

              const SizedBox(height: 16),

              _buildStatusDropdown(),

              const SizedBox(height: 16),

              if (_isAdmin) _buildDateSelector(),

              if (_isAdmin) const SizedBox(height: 16),

              // =================================================
              // SAVE BUTTON
              // Extra bottom space keeps it above Android nav bar
              // =================================================
              SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitAttendance,
                      icon: const Icon(
                        Icons.save,
                      ),
                      label: const Text(
                        'SAVE ATTENDANCE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  Widget _buildInternetStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: _hasInternet
            ? Colors.green.withOpacity(0.10)
            : Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _hasInternet
              ? Colors.green.withOpacity(0.30)
              : Colors.orange.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasInternet ? Icons.wifi : Icons.wifi_off,
            color: _hasInternet ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            _hasInternet ? 'Online' : 'Offline',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _hasInternet ? Colors.green[800] : Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 230,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                if (!_isScanning) return;

                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;

                  if (value != null && value.trim().isNotEmpty) {
                    _handleQrScan(value);
                    break;
                  }
                }
              },
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(
                    Icons.flash_on,
                  ),
                  onPressed: () {
                    _scannerController.toggleTorch();
                  },
                ),
              ),
            ),
            if (!_isScanning)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 48,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'QR Scanned',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeInput() {
    return TextField(
      controller: _empCodeController,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'EMP Code',
        hintText: 'Scan QR or enter EMP Code',
        prefixIcon: const Icon(
          Icons.badge_outlined,
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: _isLoading
              ? null
              : () {
                  _fetchEmployeeDirectly(
                    _empCodeController.text,
                  );
                },
        ),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) {
        _fetchEmployeeDirectly(
          _empCodeController.text,
        );
      },
    );
  }

  Widget _buildEmployeeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.isEmpty ? 'Employee Name' : _name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _company.isEmpty ? 'Company' : _company,
                    style: TextStyle(
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedStatus,
      decoration: const InputDecoration(
        labelText: 'Attendance Status',
        prefixIcon: Icon(Icons.fact_check),
        border: OutlineInputBorder(),
      ),
      items: _statuses.map((status) {
        return DropdownMenuItem(
          value: status,
          child: Text(status),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          _selectedStatus = value;
        });
      },
    );
  }

  Widget _buildDateSelector() {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Attendance Date',
          prefixIcon: Icon(Icons.calendar_today),
          suffixIcon: Icon(Icons.arrow_drop_down),
          border: OutlineInputBorder(),
        ),
        child: Text(
          DateFormat(
            'dd-MM-yyyy',
          ).format(_selectedDate),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
