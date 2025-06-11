import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:event_collab/screens/event_detail_page.dart';

class MyTicketsPage extends StatefulWidget {
  const MyTicketsPage({Key? key}) : super(key: key);

  @override
  _MyTicketsPageState createState() => _MyTicketsPageState();
}

class _MyTicketsPageState extends State<MyTicketsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy - hh:mm a');
  final DateFormat _simpleDateFormat = DateFormat('MMM dd, yyyy');

  // Track expanded ticket cards
  Set<String> _expandedTickets = {};

  @override
  void initState() {
    super.initState();
    // Check for and remove tickets for unavailable events when the page loads
    _cleanUpUnavailableTickets();
  }

  // Clean up tickets for events that no longer exist or are past their date
  Future<void> _cleanUpUnavailableTickets() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Get all tickets for the current user
      final ticketsSnapshot = await _firestore
          .collection('claimed_tickets')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      // Check each ticket's event
      for (final ticketDoc in ticketsSnapshot.docs) {
        final ticketData = ticketDoc.data();
        final eventId = ticketData['eventId'] as String? ?? '';

        // Get the event document
        final eventDoc = await _firestore.collection('events').doc(eventId).get();

        if (!eventDoc.exists) {
          // Event doesn't exist anymore, delete the ticket
          await ticketDoc.reference.delete();
          continue;
        }

        final eventData = eventDoc.data() as Map<String, dynamic>;
        final eventDate = eventData['date'] as Timestamp?;
        final now = DateTime.now();

        // If event date is in the past (more than 1 day ago), delete the ticket
        if (eventDate != null && eventDate.toDate().isBefore(now.subtract(Duration(days: 1)))) {
          await ticketDoc.reference.delete();
        }
      }
    } catch (e) {
      print('Error cleaning up tickets: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    // If no user is logged in, show a login prompt
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('My Tickets'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Please log in to view your tickets',
                style: TextStyle(fontSize: 18, color: Colors.grey[700]),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Navigate to login screen
                  // You'll need to implement this navigation based on your app structure
                  // Navigator.pushNamed(context, '/login');
                },
                child: Text('Log In'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('My Tickets'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Confirmed Tickets'),
              Tab(text: 'Pending Payments'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Confirmed Tickets
            _buildConfirmedTicketsTab(currentUser),

            // Tab 2: Pending Payments
            _buildPendingPaymentsTab(currentUser),
          ],
        ),
      ),
    );
  }

  // Tab for confirmed tickets (free claimed tickets and verified paid tickets)
  Widget _buildConfirmedTicketsTab(User currentUser) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('claimed_tickets')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('claimedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        // Handle error state
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading tickets: ${snapshot.error}'),
          );
        }

        // If no tickets found
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.confirmation_number_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No confirmed tickets found',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                SizedBox(height: 8),
                Text(
                  'When your tickets are confirmed, they will appear here',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // When tickets are available
        final tickets = snapshot.data!.docs;

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: tickets.length,
          itemBuilder: (context, index) {
            final ticketData = tickets[index].data() as Map<String, dynamic>;
            final ticketId = ticketData['ticketId'] as String? ?? tickets[index].id;
            final eventId = ticketData['eventId'] as String? ?? '';
            final eventName = ticketData['eventName'] as String? ?? 'Unnamed Event';
            final claimedAt = ticketData['claimedAt'] as Timestamp?;
            final paymentId = ticketData['paymentId'] as String?;
            final isExpanded = _expandedTickets.contains(ticketId);

            // Status will be determined based on payment data
            final bool isPaid = paymentId != null;

            return Card(
              margin: EdgeInsets.only(bottom: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Ticket header
                  ListTile(
                    contentPadding: EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: isPaid ? Colors.green[100] : Colors.blue[100],
                      child: Icon(
                        isPaid ? Icons.payments_outlined : Icons.confirmation_number_outlined,
                        color: isPaid ? Colors.green[800] : Colors.blue[800],
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            eventName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        _buildTicketStatusChip(isPaid ? 'PAID' : 'FREE'),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        Text(
                          'Ticket ID: ${ticketId}...',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Confirmed on: ${claimedAt != null ? _dateFormat.format(claimedAt.toDate()) : 'Unknown date'}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[700],
                      ),
                      onPressed: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedTickets.remove(ticketId);
                          } else {
                            _expandedTickets.add(ticketId);
                          }
                        });
                      },
                    ),
                  ),

                  // Expanded ticket details
                  if (isExpanded)
                    Column(
                      children: [
                        Divider(height: 1),
                        // Ticket details section
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isPaid) ...[
                                SizedBox(height: 8),
                                _buildInfoRow(Icons.verified, 'Verified', 'Status'),
                              ],
                            ],
                          ),
                        ),

                        // Event details section
                        FutureBuilder<DocumentSnapshot>(
                          future: _firestore.collection('events').doc(eventId).get(),
                          builder: (context, eventSnapshot) {
                            if (eventSnapshot.connectionState == ConnectionState.waiting) {
                              return Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            if (eventSnapshot.hasError || !eventSnapshot.hasData || !eventSnapshot.data!.exists) {
                              return Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red),
                                    SizedBox(height: 8),
                                    Text(
                                      'This event is no longer available',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await _deleteTicket(context, ticketId, eventId);
                                      },
                                      child: Text('Remove Ticket'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final eventData = eventSnapshot.data!.data() as Map<String, dynamic>;
                            final eventDate = eventData['date'] as Timestamp?;
                            final isPastEvent = eventDate != null && eventDate.toDate().isBefore(DateTime.now());

                            return Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isPastEvent)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.orange),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline, color: Colors.orange),
                                            SizedBox(width: 8),
                                            Text(
                                              'This event has already occurred',
                                              style: TextStyle(color: Colors.orange[800]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                  // Event and ticket actions
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // View event details button
                                      OutlinedButton.icon(
                                        icon: Icon(Icons.visibility),
                                        label: Text('View Event'),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => EventDetailPage(eventId: eventId),
                                            ),
                                          );
                                        },
                                      ),

                                      // Delete ticket button
                                      OutlinedButton.icon(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        label: Text('Cancel Ticket', style: TextStyle(color: Colors.red)),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.red),
                                        ),
                                        onPressed: () {
                                          _showDeleteConfirmation(context, ticketId, eventId, eventName);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Tab for pending payments and rejected payments
  Widget _buildPendingPaymentsTab(User currentUser) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('payments')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        // Handle error state
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading payments: ${snapshot.error}'),
          );
        }

        // If no payments found
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No pending payments found',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                SizedBox(height: 8),
                Text(
                  'When you make payments for events, they will appear here',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // Filter payments that have a claimed ticket
        return FutureBuilder<QuerySnapshot>(
          future: _firestore
              .collection('claimed_tickets')
              .where('userId', isEqualTo: currentUser.uid)
              .get(),
          builder: (context, claimedTicketsSnapshot) {
            if (claimedTicketsSnapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }

            // Create a set of payment IDs that already have claimed tickets
            Set<String> claimedPaymentIds = {};
            if (claimedTicketsSnapshot.hasData) {
              for (var doc in claimedTicketsSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final paymentId = data['paymentId'] as String?;
                if (paymentId != null) {
                  claimedPaymentIds.add(paymentId);
                }
              }
            }

            // Filter payments that don't have a claimed ticket yet
            final payments = snapshot.data!.docs.where((doc) {
              return !claimedPaymentIds.contains(doc.id);
            }).toList();

            if (payments.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payment_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No pending payments found',
                      style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'When you make payments for events, they will appear here',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: payments.length,
              itemBuilder: (context, index) {
                final paymentData = payments[index].data() as Map<String, dynamic>;
                final paymentId = payments[index].id;
                final eventId = paymentData['eventId'] as String? ?? '';
                final eventName = paymentData['eventName'] as String? ?? 'Unnamed Event';
                final timestamp = paymentData['timestamp'] as Timestamp?;
                final screenshotUrl = paymentData['screenshotUrl'] as String? ?? '';
                final isVerified = paymentData['isVerified'] as bool?;
                final verifiedAt = paymentData['verifiedAt'] as Timestamp?;
                final isExpanded = _expandedTickets.contains(paymentId);

                // Determine payment status
                String status = 'Pending';
                Color statusColor = Colors.orange;
                IconData statusIcon = Icons.hourglass_empty;

                if (isVerified != null) {
                  if (isVerified) {
                    status = 'Accepted';
                    statusColor = Colors.green;
                    statusIcon = Icons.check_circle;
                  } else {
                    status = 'Rejected';
                    statusColor = Colors.red;
                    statusIcon = Icons.cancel;
                  }
                }

                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Payment header
                      ListTile(
                        contentPadding: EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.2),
                          child: Icon(statusIcon, color: statusColor),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                eventName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            _buildPaymentStatusChip(status, statusColor),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 4),
                            Text(
                              'Payment ID: ${paymentId.substring(0, 8)}...',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Submitted on: ${timestamp != null ? _dateFormat.format(timestamp.toDate()) : 'Unknown date'}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            color: Colors.grey[700],
                          ),
                          onPressed: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedTickets.remove(paymentId);
                              } else {
                                _expandedTickets.add(paymentId);
                              }
                            });
                          },
                        ),
                      ),


                      // Expanded payment details
                      if (isExpanded)
                        Column(
                          children: [
                            Divider(height: 1),
                            // Payment details section
                            Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (status != 'Pending' && verifiedAt != null) ...[
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                        status == 'Accepted' ? Icons.verified : Icons.dangerous,
                                        status == 'Accepted' ? 'Verified On' : 'Rejected On',
                                        _dateFormat.format(verifiedAt.toDate())
                                    ),
                                  ],
                                  SizedBox(height: 16),

                                  // Payment screenshot
                                  if (screenshotUrl.isNotEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Payment Screenshot',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            screenshotUrl,
                                            height: 200,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                height: 200,
                                                width: double.infinity,
                                                color: Colors.grey[200],
                                                child: Center(
                                                  child: Icon(Icons.error, color: Colors.grey[400], size: 48),
                                                ),
                                              );
                                            },
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return Container(
                                                height: 200,
                                                width: double.infinity,
                                                color: Colors.grey[200],
                                                child: Center(
                                                  child: CircularProgressIndicator(
                                                    value: loadingProgress.expectedTotalBytes != null
                                                        ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                        : null,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  SizedBox(height: 16),

                                  // Status information
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: statusColor.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(statusIcon, color: statusColor),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Status: $status',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: statusColor,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                _getStatusMessage(status),
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 16),

                                  // Action buttons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // View event details button
                                      OutlinedButton.icon(
                                        icon: Icon(Icons.visibility, size: 18),
                                        label: Text('View Event', style: TextStyle(fontSize: 12)),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => EventDetailPage(eventId: eventId),
                                            ),
                                          );
                                        },
                                      ),

                                      // Action based on status
                                      if (status == 'Rejected')
                                        OutlinedButton.icon(
                                          icon: Icon(Icons.refresh, size: 18),
                                          label: Text('Submit New Payment', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.blue,
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => EventDetailPage(eventId: eventId),
                                              ),
                                            );
                                          },
                                        )
                                      else if (status == 'Pending')
                                        OutlinedButton.icon(
                                          icon: Icon(Icons.delete, color: Colors.red, size: 18),
                                          label: Text('Cancel Payment', style: TextStyle(color: Colors.red, fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Colors.red),
                                          ),
                                          onPressed: () {
                                            _showDeletePaymentConfirmation(context, paymentId, eventName);
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Get status message based on status
  String _getStatusMessage(String status) {
    switch (status) {
      case 'Pending':
        return 'Your payment is being reviewed by the event organizer.';
      case 'Accepted':
        return 'Your payment has been verified. The ticket is now available in the Confirmed Tickets tab.';
      case 'Rejected':
        return 'Your payment was rejected. Please check the payment details and try again.';
      default:
        return '';
    }
  }

  // Build a status chip for tickets
  Widget _buildTicketStatusChip(String status) {
    Color chipColor;

    if (status == 'FREE') {
      chipColor = Colors.blue;
    } else if (status == 'PAID') {
      chipColor = Colors.green;
    } else {
      chipColor = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: chipColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // Build a status chip for payments
  Widget _buildPaymentStatusChip(String status, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Show confirmation dialog before deleting a ticket
  Future<void> _showDeleteConfirmation(BuildContext context, String ticketId, String eventId, String eventName) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Ticket'),
        content: Text('Are you sure you want to cancel your ticket for "$eventName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('No, Keep Ticket'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteTicket(context, ticketId, eventId);
            },
            child: Text('Yes, Cancel Ticket'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Show confirmation dialog before deleting a payment
  Future<void> _showDeletePaymentConfirmation(BuildContext context, String paymentId, String eventName) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Payment'),
        content: Text('Are you sure you want to cancel your payment for "$eventName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('No, Keep Payment'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePayment(context, paymentId);
            },
            child: Text('Yes, Cancel Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Delete a ticket and update the event's ticketsClaimed count
  Future<void> _deleteTicket(BuildContext context, String ticketId, String eventId) async {
    // Show the loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Cancelling ticket...'),
          ],
        ),
      ),
    );

    try {
      // Use a transaction to ensure consistency
      await _firestore.runTransaction((transaction) async {
        // Get current event data
        final eventDoc = await transaction.get(_firestore.collection('events').doc(eventId));
        if (eventDoc.exists) {
          final eventData = eventDoc.data() as Map<String, dynamic>;
          final currentTicketsClaimed = eventData['ticketsClaimed'] as int? ?? 0;

          // Update event's ticketsClaimed count (decrement by 1, but don't go below 0)
          transaction.update(
            _firestore.collection('events').doc(eventId),
            {'ticketsClaimed': (currentTicketsClaimed > 0) ? currentTicketsClaimed - 1 : 0},
          );
        }

        // Delete the ticket document
        transaction.delete(_firestore.collection('claimed_tickets').doc(ticketId));
      });

      // Close loading dialog - use Navigator.of(context, rootNavigator: true) to ensure we close the dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ticket cancelled successfully')),
      );
    } catch (e) {
      // Close loading dialog - use Navigator.of(context, rootNavigator: true) to ensure we close the dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel ticket: ${e.toString()}')),
      );
    }
  }

  // Delete a payment
  Future<void> _deletePayment(BuildContext context, String paymentId) async {
    // Show the loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Cancelling payment...'),
          ],
        ),
      ),
    );

    try {
      // Delete the payment document
      await _firestore.collection('payments').doc(paymentId).delete();

      // Close loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment cancelled successfully')),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel payment: ${e.toString()}')),
      );
    }
  }
}
