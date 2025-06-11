import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:event_collab/screens/payment_page.dart';

class EventDetailPage extends StatefulWidget {
  final String eventId;

  EventDetailPage({required this.eventId});

  @override
  _EventDetailPageState createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUserRole;
  Map<String, bool> _applicationStatus = {};
  // Track payment status for the current user and event
  String? _paymentStatus;
  bool _isPaymentVerified = false;
  bool _isPaymentRejected = false;
  bool _isDisposed = false;

  String _formatTimeString(String timeString) {
    try {
      final timeParts = timeString.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final time = TimeOfDay(hour: hour, minute: minute);
      return time.format(context);
    } catch (e) {
      return timeString; // fallback to original string if parsing fails
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  @override
  void dispose() {
    _isDisposed = true; // Set the flag when widget is disposed
    super.dispose();
  }

  void _fetchUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          // Check if widget is still mounted before setState
          if (!_isDisposed && mounted) {
            setState(() {
              _currentUserRole = userDoc.data()?['role'];
              print('User role fetched: $_currentUserRole'); // Debug print
            });
          }
        } else {
          print('User document does not exist'); // Debug print
        }
        // Fetch applications status for this user and event
        await _checkApplicationStatus(user.uid);
        // Fetch payment status for this user and event
        await _checkPaymentStatus(user.uid);
      } else {
        print('No user is currently logged in'); // Debug print
      }
    } catch (e) {
      print('Error fetching user role: $e');
    }
  }

  Future<void> _checkApplicationStatus(String userId) async {
    try {
      // Only fetch applications if user is logged in
      if (_auth.currentUser == null) return;

      final applications = await _firestore
          .collection('event_applications')
          .where('eventId', isEqualTo: widget.eventId)
          .where('userId', isEqualTo: userId)
          .get();

      Map<String, bool> status = {};

      for (var doc in applications.docs) {
        final role = doc.data()['role'] as String;
        status[role] = true;
      }

      if (mounted) {
        setState(() {
          _applicationStatus = status;
        });
      }
    } catch (e) {
      print('Error checking applications status: $e');
      // Don't show an error message to the user,
      // just silently fail and default to showing apply buttons
    }
  }

  // Check payment status for the current user and even

  // Check payment status for the current user and event
  Future<void> _checkPaymentStatus(String userId) async {
    try {
      final paymentsQuery = await _firestore
          .collection('payments')
          .where('eventId', isEqualTo: widget.eventId)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (paymentsQuery.docs.isNotEmpty) {
        final latestPayment = paymentsQuery.docs.first.data();

        // Check if the widget is still mounted before calling setState
        if (!_isDisposed && mounted) {
          setState(() {
            _paymentStatus = latestPayment['status'] as String?;
            _isPaymentVerified = latestPayment['isVerified'] == true;
            _isPaymentRejected = latestPayment['isVerified'] == false;
          });

          print('Payment status: $_paymentStatus');
          print('Payment verified: $_isPaymentVerified');
          print('Payment rejected: $_isPaymentRejected');
        }
      }
    } catch (e) {
      print('Error checking payment status: $e');
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.purple[800],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Check if the current user has already claimed a ticket for this event
  Future<bool> _hasUserClaimedTicket(String userId) async {
    try {
      final claimedTicketDoc = await _firestore
          .collection('claimed_tickets')
          .where('eventId', isEqualTo: widget.eventId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      return claimedTicketDoc.docs.isNotEmpty;
    } catch (e) {
      print('Error checking claimed ticket: $e');
      return false;
    }
  }

  // Check if the user has a pending or verified payment
  bool _hasActivePayment() {
    // If payment status is pending OR payment is verified, consider it active
    return _paymentStatus == 'pending' || _isPaymentVerified;
  }

  Future<void> _handleApplyForRole(String role, String eventName) async {
    // Check if user is logged in
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please log in to apply')),
      );
      return;
    }

    // Application form data
    String name = '';
    String contactInfo = '';
    String message = '';

    // Show application form dialog
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) => ApplicationFormDialog(role: role),
    );

    // If dialog was dismissed or canceled
    if (result == null) return;

    // Extract form data
    name = result['name'] ?? '';
    contactInfo = result['contactInfo'] ?? '';
    message = result['message'] ?? '';

    try {
      // Create application document with additional information
      await _firestore.collection('event_applications').add({
        'eventId': widget.eventId,
        'eventName': eventName,
        'userId': user.uid,
        'userEmail': user.email,
        'name': name,
        'contactInfo': contactInfo,
        'message': message,
        'role': role,
        'status': 'pending', // pending, approved, rejected
        'appliedAt': FieldValue.serverTimestamp(),
      });

      // Update local state to reflect the application
      setState(() {
        _applicationStatus[role] = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied as $role successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error applying: ${e.toString()}')),
      );
    }
  }

  Future<void> _handleGetTickets(BuildContext context, Map<String, dynamic> event) async {
    try {
      // Check if user is logged in
      final user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please log in to claim a ticket')),
        );
        return;
      }

      final isFreeTicket = event['isFreeTicket'] ?? (event['ticketPrice'] == 0);

      if (!isFreeTicket) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentFormPage(eventId: widget.eventId),
          ),
        );
        return;
      }

      // Fetch the most current event data to check ticket availability
      final eventDoc = await _firestore.collection('events').doc(widget.eventId).get();

      if (!eventDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Event not found')),
        );
        return;
      }

      final eventData = eventDoc.data()!;
      final totalTickets = eventData['totalTickets'] as int? ?? 0;
      final ticketsClaimed = eventData['ticketsClaimed'] as int? ?? 0;

      print('Total tickets: $totalTickets, Tickets claimed: $ticketsClaimed'); // Debug print

      if (ticketsClaimed >= totalTickets) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sorry, all free tickets have been claimed')),
        );
        return;
      }

      // Check if user has already claimed a ticket
      final hasClaimedTicket = await _hasUserClaimedTicket(user.uid);
      if (hasClaimedTicket) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have already claimed a ticket for this event')),
        );
        return;
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Ticket'),
          content: Text('Do you want to claim your free ticket for this event?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirm'),
            ),
          ],
        ),
      ) ?? false;

      if (confirmed) {
        // Use a transaction to ensure atomic operations
        await _firestore.runTransaction((transaction) async {
          // Get the current document to read the current ticketsClaimed value
          final eventDoc = await transaction.get(_firestore.collection('events').doc(widget.eventId));

          if (!eventDoc.exists) {
            throw Exception('Event no longer exists');
          }

          final currentTicketsClaimed = eventDoc.data()?['ticketsClaimed'] as int? ?? 0;
          final maxTickets = eventDoc.data()?['totalTickets'] as int? ?? 0;

          // Check again if tickets are available within the transaction
          if (currentTicketsClaimed >= maxTickets) {
            throw Exception('All tickets have been claimed');
          }

          // Update the event document
          transaction.update(_firestore.collection('events').doc(widget.eventId), {
            'ticketsClaimed': currentTicketsClaimed + 1,
          });

          // Create a record of the claimed ticket with user email
          final claimedTicketRef = _firestore.collection('claimed_tickets').doc();
          transaction.set(claimedTicketRef, {
            'eventId': widget.eventId,
            'userId': user.uid,
            'userEmail': user.email,  // Store the user's email
            'claimedAt': FieldValue.serverTimestamp(),
            'ticketId': claimedTicketRef.id,
            'eventName': eventData['name'] ?? 'Unnamed Event',
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket claimed successfully!')),
        );

        // Refresh the UI to show updated ticket status
        setState(() {});
      }
    } catch (e) {
      print('Error handling tickets: $e'); // More detailed error logging
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error claiming ticket: ${e.toString()}')),
      );
    }
  }

  void _shareEvent(BuildContext context, Map<String, dynamic> event) {
    try {
      // Check if ticket is free
      final isFreeTicket = event['isFreeTicket'] ?? (event['ticketPrice'] == 0);

      // Create a shareable message
      final String shareText = '''
Check out this event: ${event['name'] ?? 'Untitled Event'}

${event['description'] ?? 'No description available'}

${event['type'] == 'online' ? 'Online Event' : 'Location: ${event['location']}'}
${event['ticketPrice'] != null ? 'Price: ${event['ticketPrice']} PKR' : ''}
${isFreeTicket ? 'FREE ENTRY' : ''}

Shared via Event Collab App
'''.trim();

      Share.share(
        shareText,
        subject: 'Event: ${event['name'] ?? ''}',
        sharePositionOrigin: Rect.fromLTWH(
          0, 0,
          MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height / 2,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: ${e.toString()}')),
      );
    }
  }

  Widget _buildApplyButton(String role, String eventName) {
    final bool hasApplied = _applicationStatus[role] ?? false;

    return ElevatedButton.icon(
      icon: Icon(hasApplied ? Icons.check : Icons.person_add),
      label: Text(hasApplied ? 'Applied as $role' : 'Apply as $role'),
      onPressed: hasApplied ? null : () => _handleApplyForRole(role, eventName),
      style: ElevatedButton.styleFrom(
        backgroundColor: hasApplied ? Colors.green[100] : null,
        foregroundColor: hasApplied ? Colors.green[800] : null,
      ),
    );
  }

  // Build the ticket button text and status based on payment and ticket state
  Widget _buildTicketButton(bool hasClaimedTicket, bool isFreeTicket) {
    String buttonText;
    bool isDisabled = false;
    Color? backgroundColor;
    Color? textColor;

    if (_auth.currentUser == null) {
      buttonText = 'Login to Claim Ticket';
      isDisabled = true;
    } else if (hasClaimedTicket) {
      buttonText = 'Ticket Claimed';
      isDisabled = true;
      backgroundColor = Colors.green[100];
      textColor = Colors.green[800];
    } else if (!isFreeTicket) {
      // For paid events
      if (_paymentStatus == 'pending' && !_isPaymentVerified && !_isPaymentRejected) {
        buttonText = 'Payment Pending';
        isDisabled = true;
        backgroundColor = Colors.orange[100];
        textColor = Colors.orange[800];
      } else if (_isPaymentVerified) {
        buttonText = 'Payment Verified';
        isDisabled = true;
        backgroundColor = Colors.green[100];
        textColor = Colors.green[800];
      } else if (_isPaymentRejected) {
        buttonText = 'Get Tickets';
        isDisabled = false;
      } else {
        buttonText = 'Get Tickets';
        isDisabled = false;
      }
    } else {
      // For free events
      buttonText = 'Get Tickets';
      isDisabled = false;
    }

    return ElevatedButton(
      onPressed: isDisabled ? null : () => _handleGetTickets(context, {
        'isFreeTicket': isFreeTicket,
        'ticketPrice': isFreeTicket ? 0 : 1, // Just a placeholder for non-free tickets
      }),
      child: Text(buttonText),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 16),
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
      ),
    );
  }

  // Function to build payment status message
  Widget? _buildPaymentStatusMessage() {
    if (_auth.currentUser == null || (_paymentStatus == null && !_isPaymentVerified && !_isPaymentRejected)) {
      return null;
    }

    IconData icon;
    String message;
    Color? backgroundColor;
    Color? textColor;
    Color? iconColor;

    if (_paymentStatus == 'pending' && !_isPaymentVerified && !_isPaymentRejected) {
      icon = Icons.hourglass_empty;
      message = 'Your payment is pending verification';
      backgroundColor = Colors.orange[50];
      textColor = Colors.orange[800];
      iconColor = Colors.orange;
    } else if (_isPaymentVerified) {
      icon = Icons.check_circle;
      message = 'Your payment has been verified';
      backgroundColor = Colors.green[50];
      textColor = Colors.green[800];
      iconColor = Colors.green;
    } else if (_isPaymentRejected) {
      icon = Icons.cancel;
      message = 'Your payment was rejected. You can try again.';
      backgroundColor = Colors.red[50];
      textColor = Colors.red[800];
      iconColor = Colors.red;
    } else {
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Event Details'),
        elevation: 0,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('events').doc(widget.eventId).get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading event'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: CircularProgressIndicator());
          }

          final event = snapshot.data!.data() as Map<String, dynamic>;

          // Safely extract all fields with null checks
          final bannerImage = event['bannerImage'] as String?;
          final name = event['name'] as String? ?? 'No title';
          final description = event['description'] as String? ?? 'No description provided';
          final type = event['type'] as String? ?? 'online';
          final location = event['location'] as String?;
          final totalTickets = event['totalTickets'] as int? ?? 0;
          final ticketPrice = event['ticketPrice'] as num? ?? 0.0;
          final lookingFor = (event['lookingFor'] as List?)?.cast<String>() ?? <String>[];
          print('Event is looking for: $lookingFor'); // Debug print
          final createdAt = event['createdAt'] as Timestamp?;
          final isFreeTicket = event['isFreeTicket'] ?? (ticketPrice == 0);
          final ticketsClaimed = event['ticketsClaimed'] as int? ?? 0;
          final startDate = event['startDate'] as Timestamp?;
          final endDate = event['endDate'] as Timestamp?;
          final startTime = event['startTime'] as String?;
          final endTime = event['endTime'] as String?;
          final dateFormat = DateFormat('MMM dd, yyyy');
          final timeFormat = DateFormat('hh:mm a');

          // Check if current user has already claimed a ticket
          return StreamBuilder<bool>(
            stream: _auth.currentUser != null
                ? Stream.fromFuture(_hasUserClaimedTicket(_auth.currentUser!.uid))
                : Stream.value(false),
            builder: (context, hasClaimedSnapshot) {
              final hasClaimedTicket = hasClaimedSnapshot.data ?? false;

              return SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: bannerImage != null
                          ? Image.network(
                        bannerImage,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 200,
                          color: Colors.grey[200],
                          child: Icon(Icons.broken_image, size: 50),
                        ),
                      )
                          : Container(
                        height: 200,
                        color: Colors.grey[200],
                        child: Icon(Icons.image, size: 50),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Event Name
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),

                    // Event Type and Location
                    _buildDetailRow(
                      type == 'onsite' ? Icons.location_on : Icons.public,
                      type == 'onsite'
                          ? location ?? 'Location not specified'
                          : 'Online Event',
                    ),
                    SizedBox(height: 16),

                    // Description Section
                    _buildSectionTitle('Description'),
                    Text(
                      description,
                      style: TextStyle(fontSize: 16, height: 1.5),
                    ),
                    SizedBox(height: 20),

                    // Date and Time Section
                    _buildSectionTitle('Date & Time'),
                    if (startDate != null && startTime != null)
                      _buildDetailRow(
                        Icons.calendar_today,
                        'Starts: ${dateFormat.format(startDate!.toDate())} at ${_formatTimeString(startTime!)}',
                      ),
                    if (endDate != null && endTime != null)
                      _buildDetailRow(
                        Icons.calendar_today,
                        'Ends: ${dateFormat.format(endDate!.toDate())} at ${_formatTimeString(endTime!)}',
                      ),
                    SizedBox(height: 20),

                    // Event Details Section
                    _buildSectionTitle('Event Details'),
                    _buildDetailRow(
                      Icons.confirmation_number,
                      'Total Tickets: $totalTickets',
                    ),
                    _buildDetailRow(
                      Icons.people,
                      'Tickets Claimed: $ticketsClaimed / $totalTickets',
                    ),
                    _buildDetailRow(
                      Icons.attach_money,
                      'Ticket Price: ${isFreeTicket ? 'FREE' : '${ticketPrice.toStringAsFixed(2)} PKR'}',
                    ),
                    if (createdAt != null)
                      _buildDetailRow(
                        Icons.calendar_today,
                        'Created on: ${dateFormat.format(createdAt.toDate())}',
                      ),
                    SizedBox(height: 20),

                    // Looking For Section (if available)
                    if (lookingFor.isNotEmpty) ...[
                      _buildSectionTitle('Looking For'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: lookingFor.map((item) => Chip(
                          label: Text(item),
                          backgroundColor: Colors.purple[50],
                          labelStyle: TextStyle(color: Colors.purple[800]),
                        )).toList(),
                      ),

                      // Application buttons based on user role and event needs
                      if (_auth.currentUser != null && _currentUserRole != null) ...[
                        SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Show apply buttons only if the user role matches what the event is looking for
                            if (_currentUserRole == 'Sponsor' && lookingFor.contains('Sponsor'))
                              Container(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                width: double.infinity,
                                child: _buildApplyButton('Sponsor', name),
                              ),

                            if (_currentUserRole == 'Vendor' && lookingFor.contains('Vendor'))
                              Container(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                width: double.infinity,
                                child: _buildApplyButton('Vendor', name),
                              ),

                            if (_currentUserRole == 'Volunteer' && lookingFor.contains('Volunteer'))
                              Container(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                width: double.infinity,
                                child: _buildApplyButton('Volunteer', name),
                              ),
                          ],
                        ),
                      ],
                      SizedBox(height: 20),
                    ],

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildTicketButton(hasClaimedTicket, isFreeTicket),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _shareEvent(context, event);
                            },
                            child: Text('Share Event'),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Show message if user has already claimed a ticket
                    if (hasClaimedTicket)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            border: Border.all(color: Colors.green[200]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You have already claimed a ticket for this event',
                                  style: TextStyle(color: Colors.green[800]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Show payment status message if applicable
                    if (!isFreeTicket) ...[
                      // Only show payment status for paid events
                      if (_buildPaymentStatusMessage() != null)
                        _buildPaymentStatusMessage()!,
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Create a new dialog widget for application form
class ApplicationFormDialog extends StatefulWidget {
  final String role;

  ApplicationFormDialog({required this.role});

  @override
  _ApplicationFormDialogState createState() => _ApplicationFormDialogState();
}

class _ApplicationFormDialogState extends State<ApplicationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Apply as ${widget.role}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please provide the following information:'),
              SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                decoration: InputDecoration(
                  labelText: 'Contact Information',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: 'Phone number or alternate email',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter contact information';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                decoration: InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                  hintText: 'Why are you interested in this role?',
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a message';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text.trim(),
                'contactInfo': _contactController.text.trim(),
                'message': _messageController.text.trim(),
              });
            }
          },
          child: Text('Submit Application'),
        ),
      ],
    );
  }
}