import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class EventReportPage extends StatefulWidget {
  final String eventId;

  const EventReportPage({Key? key, required this.eventId}) : super(key: key);

  @override
  _EventReportPageState createState() => _EventReportPageState();
}

class _EventReportPageState extends State<EventReportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Future<List<Map<String, dynamic>>> _userDataFuture;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _fetchUserData();
  }

  Future<List<Map<String, dynamic>>> _fetchUserData() async {
    final List<Map<String, dynamic>> result = [];


    try {
      debugPrint('Fetching tickets for event: ${widget.eventId}');
      final ticketDocs = await _firestore
          .collection('claimed_tickets')
          .where('eventId', isEqualTo: widget.eventId)
          .get();

      debugPrint('Found ${ticketDocs.docs.length} tickets');

      for (final ticket in ticketDocs.docs) {
        final ticketData = ticket.data();
        final userId = ticketData['userId'];

        debugPrint('Processing ticket ${ticket.id} for user $userId');

        if (userId != null) {
          try {
            final userDoc = await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists) {
              result.add({
                'ticketId': ticket.id,
                'username': userDoc['userName'] ?? 'N/A',
                'email': userDoc['email'] ?? 'N/A',
                'claimedAt': ticketData['claimedAt'],
                'eventId': ticketData['eventId'],
              });
            }
          } catch (e) {
            debugPrint('Error fetching user $userId: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching tickets: $e');
      throw Exception('Failed to load data: $e');
    }

    return result;
  }

  Future<void> _refreshData() async {
    setState(() {
      _userDataFuture = _fetchUserData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Event Report'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _userDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading report data...'),
                  ],
                )
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(snapshot.error.toString(), style: TextStyle(color: Colors.red)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('No ticket holders found for this event'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: Text('Refresh'),
                  ),
                ],
              ),
            );
          }

          final userData = snapshot.data!;
          return _buildReportTable(userData);
        },
      ),
    );
  }

  Widget _buildReportTable(List<Map<String, dynamic>> userData) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.table_chart),
                label: Text('Export to Excel'),
                onPressed: () => _exportToExcel(userData),
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.text_snippet),
                label: Text('Export to CSV'),
                onPressed: () => _exportToCSV(userData),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Ticket ID')),
                DataColumn(label: Text('Username')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Claimed At')),
              ],
              rows: userData.map((user) => DataRow(
                cells: [
                  DataCell(Text(user['ticketId'])),
                  DataCell(Text(user['username'])),
                  DataCell(Text(user['email'])),
                  DataCell(Text(
                      user['claimedAt'] != null
                          ? DateFormat('MMM dd, yyyy - hh:mm a')
                          .format((user['claimedAt'] as Timestamp).toDate())
                          : 'N/A'
                  )),
                ],
              )).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportToCSV(List<Map<String, dynamic>> userData) async {
    try {
      final csvData = [
        ['Ticket ID', 'Username', 'Email', 'Claim Date', 'Event ID'],
        ...userData.map((user) => [
          user['ticketId'],
          user['username'],
          user['email'],
          user['claimedAt'] != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(
              (user['claimedAt'] as Timestamp).toDate())
              : 'N/A',
          user['eventId'],
        ])
      ];

      final csvString = const ListToCsvConverter().convert(csvData);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ticket_report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csvString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Event Ticket Report',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export CSV: $e')),
      );
    }
  }

  Future<void> _exportToExcel(List<Map<String, dynamic>> userData) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Ticket Report'];

      sheet.appendRow(['Ticket ID', 'Username', 'Email', 'Claim Date', 'Event ID']);

      for (final user in userData) {
        sheet.appendRow([
          user['ticketId'],
          user['username'],
          user['email'],
          user['claimedAt'] != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(
              (user['claimedAt'] as Timestamp).toDate())
              : 'N/A',
          user['eventId'],
        ]);
      }

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/ticket_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Event Ticket Report',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export Excel: $e')),
      );
    }
  }
}