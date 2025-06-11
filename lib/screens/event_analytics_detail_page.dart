import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'event_report_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:event_collab/screens/payments_dashboard.dart';
import 'package:event_collab/screens/event_applications_page.dart';

class EventAnalyticsDetailPage extends StatelessWidget {
  final String eventId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  EventAnalyticsDetailPage({required this.eventId});

  // Function to show the email composition dialog
  void _showEmailComposerDialog(BuildContext context) {
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController bodyController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Email Ticket Holders'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subjectController,
                  decoration: InputDecoration(
                    labelText: 'Email Subject',
                    hintText: 'Enter email subject',
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: bodyController,
                  decoration: InputDecoration(
                    labelText: 'Email Body',
                    hintText: 'Enter email message to ticket holders',
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (subjectController.text.isNotEmpty && bodyController.text.isNotEmpty) {
                  Navigator.of(context).pop();
                  _sendEmailToTicketHolders(
                    context,
                    subjectController.text.trim(),
                    bodyController.text.trim(),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter both subject and body'))
                  );
                }
              },
              child: Text('Send Emails'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendEmailToTicketHolders(
      BuildContext context,
      String subject,
      String body
      ) async {
    bool operationCompleted = false;
    List<String> emailList = [];
    String? eventName;
    String? errorMessage;

    // Show loading indicator
    // Show loading indicator with a BuildContext that we save for reliable dismissal
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        dialogContext = context;
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Fetching email addresses..."),
            ],
          ),
        );
      },
    );

    try {
      print("Starting email fetch process...");

      // Get all claimed tickets for this event
      print("Fetching claimed tickets for event: $eventId");
      final ticketsSnapshot = await _firestore
          .collection('claimed_tickets')
          .where('eventId', isEqualTo: eventId)
          .get();

      print("Claimed tickets fetched: ${ticketsSnapshot.docs.length}");

      // If no tickets, set error message and return
      if (ticketsSnapshot.docs.isEmpty) {
        print("No ticket holders found");
        errorMessage = 'No ticket holders found for this event';
        return;
      }

      // Get event details (for the email)
      print("Fetching event details");
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventData = eventDoc.data() as Map<String, dynamic>?;
      eventName = eventData?['name'] ?? 'Event';
      print("Event name: $eventName");

      // MODIFIED APPROACH: Get emails directly from claimed_tickets
      // This assumes you've modified your app to store user email in claimed_tickets
      for (var doc in ticketsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final email = data['userEmail'] as String?;

        if (email != null && email.isNotEmpty) {
          emailList.add(email);
          print("Added email: $email");
        }
      }

      print("Total emails collected: ${emailList.length}");

      // If no emails found, set error message
      if (emailList.isEmpty) {
        errorMessage = 'No email addresses found for ticket holders';
        return;
      }

      // Create email URI
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: '',
        queryParameters: {
          'subject': subject,
          'body': body,
          'bcc': emailList.join(','),
        },
      );

      // Launch email client
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);

        // Try to log the email sending
        try {
          await _firestore.collection('email_logs').add({
            'eventId': eventId,
            'eventName': eventName,
            'subject': subject,
            'recipientCount': emailList.length,
            'sentAt': FieldValue.serverTimestamp(),
            'sentBy': FirebaseAuth.instance.currentUser?.uid,
          });
          print("Email log created successfully");
        } catch (logError) {
          print("Could not create email log: $logError");
        }

        operationCompleted = true;
      } else {
        errorMessage = 'Could not open email client';
      }

    }  catch (e) {
      print("Error in email sending process: ${e.toString()}");
      errorMessage = 'Failed to prepare emails: ${e.toString()}';
    } finally {
      // Ensure dialog is dismissed first, using the specific dialog context
      if (dialogContext != null) {
        Navigator.of(dialogContext!, rootNavigator: true).pop();
      }

      // Then show any messages if the main context is still valid
      if (context.mounted) {
        if (errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage))
          );
        } else if (operationCompleted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Email opened with ${emailList.length} recipients'))
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Event Analytics'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('events').doc(eventId).get(),
        builder: (context, eventSnapshot) {
          if (eventSnapshot.hasError) {
            return Center(child: Text('Error loading event analytics'));
          }

          if (!eventSnapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var event = eventSnapshot.data!.data() as Map<String, dynamic>;
          final eventName = event['name'] ?? 'Event';  // Add this line
          final totalTickets = event['totalTickets'] as int? ?? 0;
          final ticketPrice = event['ticketPrice'] as num? ?? 0.0;
          final isFreeTicket = event['isFreeTicket'] ?? (ticketPrice == 0);
          final ticketsClaimed = event['ticketsClaimed'] as int? ?? 0;

          // Format currency
          final currencyFormat = NumberFormat.currency(symbol: '');

          return StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('claimed_tickets')
                .where('eventId', isEqualTo: eventId)
                .orderBy('claimedAt', descending: true)  // Add sorting
                .snapshots(),
            builder: (context, ticketsSnapshot) {
              if (ticketsSnapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              if (ticketsSnapshot.hasError) {
                print('Ticket data error: ${ticketsSnapshot.error}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error loading ticket data'),
                      SizedBox(height: 10),
                      Text(
                        ticketsSnapshot.error.toString(),
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              final List<DocumentSnapshot> ticketDocs = ticketsSnapshot.hasData
                  ? ticketsSnapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>?;
                return data != null &&
                    data['eventId'] == eventId &&
                    data['claimedAt'] != null;
              }).toList()
                  : [];

              // Use the actual claimed tickets count from tickets collection if available
              final actualTicketsClaimed = ticketDocs.length;

              // Calculate actual vs. expected ticket claims (validation)
              final displayTicketsClaimed = actualTicketsClaimed > 0 ?
              actualTicketsClaimed : ticketsClaimed;

              // Calculate revenue (for paid events)
              final revenue = isFreeTicket ? 0.0 : ticketPrice * displayTicketsClaimed;

              // Group ticket claims by date to create time series data for charts
              Map<String, int> ticketsByDate = {};

              if (ticketDocs.isNotEmpty) {
                for (var doc in ticketDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final claimedAt = data['claimedAt'] as Timestamp?;

                  if (claimedAt != null) {
                    final dateStr = DateFormat('MMM dd').format(claimedAt.toDate());
                    ticketsByDate[dateStr] = (ticketsByDate[dateStr] ?? 0) + 1;
                  }
                }
              }

              return SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['name'] ?? 'Event Analytics',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 20),

                    // In your event management page or dashboard for organizers

                    // Single card containing all action buttons
                    Card(
                      margin: EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Event Actions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            // Generate Report
                            ListTile(
                              leading: Icon(Icons.assignment),
                              title: Text('Generate Report'),
                              trailing: Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EventReportPage(eventId: eventId),
                                  ),
                                );
                              },
                            ),
                            Divider(),

                            // Email Attendees
                            ListTile(
                              leading: Icon(Icons.email),
                              title: Text('Email Attendees'),
                              trailing: Icon(Icons.chevron_right),
                              onTap: () => _showEmailComposerDialog(context),
                            ),
                            Divider(),

                            // Submitted Payments
                            // Only show "Submitted Payments" if the event is NOT free
                            if (!isFreeTicket) ...[
                              ListTile(
                                leading: Icon(Icons.payment),
                                title: Text('Submitted Payments'),
                                trailing: Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AdminPaymentsPage(eventId: eventId),
                                    ),
                                  );
                                },
                              ),
                              Divider(),
                            ],

                            ListTile(
                              leading: Icon(Icons.people),
                              title: Text('View Applications'),
                              trailing: Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EventApplicationsPage(
                                      eventId: eventId,
                                      eventName: eventName,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Basic Stats
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildStatItem('Total Tickets', '$totalTickets'),
                            Divider(),
                            _buildStatItem(
                                'Ticket Price',
                                isFreeTicket ? 'FREE' : '${currencyFormat.format(ticketPrice)} PKR'
                            ),
                            Divider(),
                            _buildStatItem('Tickets Claimed', '$displayTicketsClaimed'),
                            Divider(),
                            _buildStatItem(
                                'Revenue Generated',
                                isFreeTicket ? 'FREE EVENT' : '${currencyFormat.format(revenue)} PKR'
                            ),
                            Divider(),
                            _buildStatItem(
                                'Capacity Filled',
                                '${totalTickets > 0 ? ((displayTicketsClaimed / totalTickets) * 100).toStringAsFixed(1) : 0}%'
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Tickets Sales Chart (Time Series)
                    Text(
                      'Ticket Claims Over Time',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    ticketsByDate.isEmpty
                        ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          'No ticket claim data available yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                        : Container(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          barGroups: _createBarChartData(ticketsByDate),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final dates = ticketsByDate.keys.toList();
                                  if (value >= 0 && value < dates.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        dates[value.toInt()],
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                                reservedSize: 30,
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toInt().toString(),
                                    style: TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: FlGridData(
                            drawHorizontalLine: true,
                            drawVerticalLine: false,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 30),

                    // Ticket Type Distribution (for future use)
                    Text(
                      'Capacity Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Container(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              color: Colors.blue,
                              value: displayTicketsClaimed.toDouble(),
                              title: 'Claimed\n$displayTicketsClaimed',
                              radius: 60,
                              titleStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.grey.shade300,
                              value: (totalTickets - displayTicketsClaimed).toDouble(),
                              title: 'Available\n${totalTickets - displayTicketsClaimed}',
                              radius: 60,
                              titleStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Future feature suggestion
                    if (ticketDocs.isEmpty)
                      Card(
                        color: Colors.amber.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Analytics Tip',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'As users claim tickets, you\'ll see real-time analytics here. Share your event to get more attendees!',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  List<BarChartGroupData> _createBarChartData(Map<String, int> ticketsByDate) {
    List<BarChartGroupData> barGroups = [];
    final dates = ticketsByDate.keys.toList();

    for (int i = 0; i < dates.length; i++) {
      final date = dates[i];
      final count = ticketsByDate[date] ?? 0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count.toDouble(),
              color: Colors.blue,
              width: 16,
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
    }

    return barGroups;
  }
}