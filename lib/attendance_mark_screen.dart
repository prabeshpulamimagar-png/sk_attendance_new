import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AttendanceMarkScreen extends StatefulWidget {
  final String username;
  final String role;

  const AttendanceMarkScreen({
    Key? key,
    required this.username,
    required this.role,
  }) : super(key: key);

  @override
  State<AttendanceMarkScreen> createState() => _AttendanceMarkScreenState();
}

class _AttendanceMarkScreenState extends State<AttendanceMarkScreen> {
  final TextEditingController _empCodeController = TextEditingController();

  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 1000,
  );

  String name = "";
  String company = "";

  bool isLoading = false;
  bool isScanning = true;

  String selectedStatus = 'Present';

  // Team Leader will automatically use today's date.
  // Admin can change the date from the UI.
  DateTime selectedDate = DateTime.now();

  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;

  final List<String> statusList = [
    'Present',
    'Absent',
    'Week Off',
    'Idle',
    'Sick',
    'Duty Return',
    'Duty Stop',
    'Cash',
  ];

  // ==========================================================
  // GOOGLE APPS SCRIPT URL
  // ==========================================================

  final String scriptUrl =
      "https://script.google.com/macros/s/AKfycbzHCmkMg-_e-GflpKI28XNQ0b7ECmq9TucAfnbVp1R6UhQLo7WYAsmCTTRsY06q2GbRxw/exec";

  // ==========================================================
  // CHECK ROLE
  // ==========================================================

  bool get isAdmin => widget.role.trim().toLowerCase() == 'admin';

  bool get isTeamLeader => widget.role.trim().toLowerCase() == 'team leader';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final bool online = !results.contains(ConnectivityResult.none);

      if (online) {
        syncOfflineAttendance();
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      syncOfflineAttendance();
    });
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    connectivitySubscription?.cancel();
    cameraController.dispose();
    _empCodeController.dispose();
    super.dispose();
  }

  // ==========================================================
  // INTERNET CHECK
  // ==========================================================

  Future<bool> hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();

      if (results.contains(ConnectivityResult.none)) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // QR SCAN
  // ==========================================================

  void handleQrScan(String scannedCode) {
    if (!isScanning) return;

    scannedCode = scannedCode.trim();

    if (scannedCode.isEmpty) return;

    setState(() {
      isScanning = false;
      _empCodeController.text = scannedCode;
    });

    fetchEmployeeDirectly(scannedCode);
  }

  // ==========================================================
  // SEARCH EMPLOYEE
  // ==========================================================

  Future<void> fetchEmployeeDirectly(String empCode) async {
    empCode = empCode.trim();

    if (empCode.isEmpty) return;

    setState(() {
      isLoading = true;
      name = "";
      company = "";
    });

    if (!await hasInternet()) {
      setState(() {
        isLoading = false;
        isScanning = true;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No Internet: You can submit attendance offline."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      return;
    }

    try {
      final url = Uri.parse(
        '$scriptUrl'
        '?action=getEmployee'
        '&empCode=${Uri.encodeComponent(empCode)}',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          if (!mounted) return;

          setState(() {
            name = data['name']?.toString() ?? "";
            company = data['company']?.toString() ?? "";
          });
        } else {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data['message']?.toString() ?? "Employee not found",
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Offline or server unreachable. "
            "Attendance will be saved locally.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isScanning = true;
        });
      }
    }
  }

  // ==========================================================
  // SAVE OFFLINE ATTENDANCE
  // ==========================================================

  Future<void> saveOfflineAttendance({
    required String empCode,
    required String date,
    required String status,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> queue = prefs.getStringList('offline_attendance') ?? [];

    final record = {
      'empCode': empCode,
      'date': date,
      'status': status,

      // IMPORTANT:
      // Save logged-in Team Leader information
      // with offline attendance.
      'username': widget.username,
      'role': widget.role,
    };

    queue.add(jsonEncode(record));

    await prefs.setStringList(
      'offline_attendance',
      queue,
    );
  }

  // ==========================================================
  // SYNC OFFLINE ATTENDANCE
  // ==========================================================

  Future<void> syncOfflineAttendance() async {
    if (!await hasInternet()) return;

    final prefs = await SharedPreferences.getInstance();

    final List<String> queue = prefs.getStringList('offline_attendance') ?? [];

    if (queue.isEmpty) return;

    final List<String> remaining = [];

    for (final item in queue) {
      try {
        final record = Map<String, dynamic>.from(
          jsonDecode(item),
        );

        final String empCode = record['empCode']?.toString() ?? "";

        final String date = record['date']?.toString() ?? "";

        final String status = record['status']?.toString() ?? "";

        // For old offline records, use current logged-in user
        // as fallback.
        final String username =
            record['username']?.toString().trim().isNotEmpty == true
                ? record['username'].toString()
                : widget.username;

        final String role = record['role']?.toString().trim().isNotEmpty == true
            ? record['role'].toString()
            : widget.role;

        if (empCode.isEmpty || date.isEmpty || status.isEmpty) {
          continue;
        }

        final url = Uri.parse(
          '$scriptUrl'
          '?action=saveAttendance'
          '&empCode=${Uri.encodeComponent(empCode)}'
          '&date=${Uri.encodeComponent(date)}'
          '&status=${Uri.encodeComponent(status)}'
          '&username=${Uri.encodeComponent(username)}'
          '&role=${Uri.encodeComponent(role)}',
        );

        final response =
            await http.get(url).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['success'] != true) {
            remaining.add(item);
          }
        } else {
          remaining.add(item);
        }
      } catch (e) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(
      'offline_attendance',
      remaining,
    );

    if (queue.length > remaining.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Offline attendance synced successfully!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================================
  // SUBMIT ATTENDANCE
  // ==========================================================

  Future<void> submitAttendance() async {
    if (isLoading) return;

    final String empCode = _empCodeController.text.trim();

    if (empCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please scan or enter employee code first!"),
        ),
      );

      return;
    }

    // ========================================================
    // TEAM LEADER
    // Always use today's date.
    //
    // ADMIN
    // Can use selected date.
    // ========================================================

    final DateTime attendanceDate =
        isTeamLeader ? DateTime.now() : selectedDate;

    final String dateString = DateFormat('yyyy-MM-dd').format(
      attendanceDate,
    );

    setState(() {
      isLoading = true;
    });

    final bool online = await hasInternet();

    // ========================================================
    // ONLINE
    // ========================================================

    if (online) {
      try {
        final url = Uri.parse(
          '$scriptUrl'
          '?action=saveAttendance'
          '&empCode=${Uri.encodeComponent(empCode)}'
          '&date=${Uri.encodeComponent(dateString)}'
          '&status=${Uri.encodeComponent(selectedStatus)}'
          '&username=${Uri.encodeComponent(widget.username)}'
          '&role=${Uri.encodeComponent(widget.role)}',
        );

        final response =
            await http.get(url).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (!mounted) return;

          if (data['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Attendance saved successfully!"),
                backgroundColor: Colors.green,
              ),
            );

            clearAfterSave();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  data['message']?.toString() ?? "Failed to save",
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        // ====================================================
        // INTERNET EXISTS BUT SERVER ERROR
        // SAVE OFFLINE
        // ====================================================

        await saveOfflineAttendance(
          empCode: empCode,
          date: dateString,
          status: selectedStatus,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Network error: Saved offline locally."),
            backgroundColor: Colors.orange,
          ),
        );

        clearAfterSave();
      }
    }

    // ========================================================
    // OFFLINE
    // ========================================================

    else {
      await saveOfflineAttendance(
        empCode: empCode,
        date: dateString,
        status: selectedStatus,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No internet: Attendance saved offline successfully.",
          ),
          backgroundColor: Colors.orange,
        ),
      );

      clearAfterSave();
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ==========================================================
  // CLEAR AFTER SAVE
  // ==========================================================

  void clearAfterSave() {
    _empCodeController.clear();

    setState(() {
      name = "";
      company = "";
      selectedStatus = 'Present';

      // Always reset to today's date.
      selectedDate = DateTime.now();

      isScanning = true;
    });
  }

  // ==========================================================
  // BUILD UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/sk_new_logo.png',
              height: 28,
              width: 28,
            ),
            const SizedBox(width: 10),
            const Text('Attendance'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==================================================
            // QR SCANNER
            // ==================================================

            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: cameraController,
                  onDetect: (capture) {
                    if (!isScanning) return;

                    for (final barcode in capture.barcodes) {
                      final String? value = barcode.rawValue;

                      if (value != null && value.trim().isNotEmpty) {
                        handleQrScan(value);
                        break;
                      }
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: () {
                setState(() {
                  isScanning = true;
                });
              },
              child: const Text("Tap here to Scan Again"),
            ),

            const SizedBox(height: 10),

            // ==================================================
            // EMP CODE SEARCH
            // ==================================================

            TextField(
              controller: _empCodeController,
              decoration: InputDecoration(
                labelText: 'EMP Code',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => fetchEmployeeDirectly(
                    _empCodeController.text.trim(),
                  ),
                ),
              ),
              onSubmitted: (value) => fetchEmployeeDirectly(
                value.trim(),
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // EMPLOYEE INFORMATION
            // ==================================================

            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Name: ${name.isEmpty ? '-' : name}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Company: ${company.isEmpty ? '-' : company}",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // STATUS
            // ==================================================

            DropdownButtonFormField<String>(
              value: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Select Status',
                border: OutlineInputBorder(),
              ),
              items: statusList.map(
                (String status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status),
                  );
                },
              ).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedStatus = newValue;
                  });
                }
              },
            ),

            // ==================================================
            // ATTENDANCE DATE
            //
            // ADMIN ONLY
            //
            // TEAM LEADER:
            // DATE FIELD IS COMPLETELY HIDDEN.
            // SUBMIT USES TODAY'S DATE AUTOMATICALLY.
            // ==================================================

            if (isAdmin) ...[
              const SizedBox(height: 20),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );

                  if (picked != null) {
                    setState(() {
                      selectedDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Attendance Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(
                      Icons.calendar_month,
                    ),
                  ),
                  child: Text(
                    DateFormat(
                      'dd-MM-yyyy',
                    ).format(
                      selectedDate,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ==================================================
            // SUBMIT BUTTON
            // ==================================================

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                ),
                backgroundColor: Colors.blue,
              ),
              onPressed: isLoading ? null : submitAttendance,
              child: const Text(
                'Submit Attendance',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
