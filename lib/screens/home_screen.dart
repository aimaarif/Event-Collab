import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:event_collab/auth_service.dart';
import 'package:event_collab/config/api_config.dart';
import 'package:event_collab/screens/auth_screen.dart';
import 'package:event_collab/screens/profile_page.dart';
import 'package:event_collab/screens/event_detail_page.dart';
import 'package:event_collab/screens/ai_chatbot_screen.dart';
import 'package:event_collab/services/huggingface_service.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isProcessingDeletion = false;
  bool _aiRecommendationsExpanded = false;
  String? _aiRecommendationsText;
  bool _aiRecommendationsLoading = false;

  @override
  void initState() {
    super.initState();
    // Run the deletion process once when the screen is first loaded
    _runExpiredEventsCleanup();
  }

  // New method to run deletion with proper error handling
  Future<void> _runExpiredEventsCleanup() async {
    if (_isProcessingDeletion) return; // Prevent concurrent executions

    setState(() {
      _isProcessingDeletion = true;
    });

    try {
      print("Starting expired events cleanup...");
      await _deleteExpiredEvents();
      print("Expired events cleanup completed successfully.");
    } catch (e) {
      print("Error during expired events cleanup: $e");
      // Optional: Show a snackbar with the error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to clean up expired events: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingDeletion = false;
        });
      }
    }
  }

  Future<void> _deleteExpiredEvents() async {
    final now = DateTime.now();
    print("Current date and time for deletion check: ${now.toString()}");

    // Get all events that end today or in the past
    final DateTime startOfTomorrow = DateTime(now.year, now.month, now.day).add(Duration(days: 1));
    print("Checking events ending before: ${startOfTomorrow.toString()}");

    // Improved query to get events ending today or earlier
    QuerySnapshot eventsQuery;
    try {
      eventsQuery = await _firestore.collection('events')
          .where('endDate', isLessThan: Timestamp.fromDate(startOfTomorrow))
          .get();
      print("Found ${eventsQuery.docs.length} events to check for expiration");
    } catch (e) {
      print("Error querying events: $e");
      rethrow; // Re-throw to be caught by caller
    }

    int deletedCount = 0;
    List<String> deletedEvents = []; // Track which events were deleted for debugging

    // We need to use multiple batches because:
    // 1. We need to query for related records first
    // 2. Firebase batch has a 500 operations limit
    for (final doc in eventsQuery.docs) {
      try {
        final event = doc.data() as Map<String, dynamic>;
        final String eventName = event['name'] ?? 'Unknown event';
        final eventId = doc.id;

        final endDate = (event['endDate'] as Timestamp).toDate();
        final endTimeStr = event['endTime'] as String?;

        print("Checking event '$eventName' (ID: $eventId)");
        print("  - End date: ${endDate.toString()}");
        print("  - End time string: $endTimeStr");

        bool shouldDelete = false;

        // If endDate is before today, delete immediately
        if (endDate.year < now.year ||
            (endDate.year == now.year && endDate.month < now.month) ||
            (endDate.year == now.year && endDate.month == now.month && endDate.day < now.day)) {
          print("  - DELETING: Event date is in the past");
          shouldDelete = true;
        }
        // For events ending today, check the time
        else if (endDate.year == now.year && endDate.month == now.month && endDate.day == now.day) {
          print("  - Event ends today, checking time");

          // Parse the end time
          TimeOfDay? endTime;
          if (endTimeStr != null) {
            final parts = endTimeStr.split(':');
            if (parts.length == 2) {
              try {
                endTime = TimeOfDay(
                  hour: int.parse(parts[0]),
                  minute: int.parse(parts[1]),
                );
                print("  - Parsed end time: ${endTime.hour}:${endTime.minute}");
              } catch (e) {
                print("  - Error parsing end time: $e");
              }
            }
          }

          // If no endTime specified, handle that case
          if (endTime == null) {
            print("  - KEEPING: No valid end time specified for today's event");
            continue;
          } else {
            // Check if the event's end time has passed
            final currentTime = TimeOfDay(hour: now.hour, minute: now.minute);

            // Compare times (convert to minutes since midnight for easier comparison)
            final eventEndMinutes = endTime.hour * 60 + endTime.minute;
            final currentMinutes = currentTime.hour * 60 + currentTime.minute;

            print("  - Current time: ${currentTime.hour}:${currentTime.minute} ($currentMinutes mins)");
            print("  - Event end time: ${endTime.hour}:${endTime.minute} ($eventEndMinutes mins)");

            if (eventEndMinutes <= currentMinutes) {
              print("  - DELETING: Event time has passed");
              shouldDelete = true;
            } else {
              print("  - KEEPING: Event time has not passed yet");
            }
          }
        }

        // If the event should be deleted, handle the deletion of related records
        if (shouldDelete) {
          await _deleteEventAndRelatedRecords(eventId, eventName);
          deletedCount++;
          deletedEvents.add("$eventName");
        }
      } catch (e) {
        print("Error processing event ${doc.id}: $e");
        // Continue to next document instead of failing the entire batch
      }
    }

    print("Deleted $deletedCount events: ${deletedEvents.join(', ')}");
  }

// New method to handle deletion of an event and all its related records
  Future<void> _deleteEventAndRelatedRecords(String eventId, String eventName) async {
    print("Starting deletion process for event '$eventName' (ID: $eventId)");

    // Create a new batch for this specific event deletion
    final WriteBatch batch = _firestore.batch();
    int operationCount = 0;

    // Step 1: Get all related records that need to be deleted

    // 1.1: Get payments related to this event
    final QuerySnapshot paymentsQuery = await _firestore.collection('payments')
        .where('eventId', isEqualTo: eventId)
        .get();
    print("  - Found ${paymentsQuery.docs.length} payments to delete");

    // 1.2: Get claimed tickets related to this event
    final QuerySnapshot claimedTicketsQuery = await _firestore.collection('claimed_tickets')
        .where('eventId', isEqualTo: eventId)
        .get();
    print("  - Found ${claimedTicketsQuery.docs.length} claimed tickets to delete");

    // 1.3: Get applications related to this event
    final QuerySnapshot applicationsQuery = await _firestore.collection('event_applications')
        .where('eventId', isEqualTo: eventId)
        .get();
    print("  - Found ${applicationsQuery.docs.length} applications to delete");

    // Function to commit the current batch if needed and start a new one
    Future<void> commitBatchIfNeeded() async {
      if (operationCount >= 450) { // Leave some buffer below the 500 limit
        print("  - Committing batch with $operationCount operations");
        await batch.commit();
        operationCount = 0;
      }
    }

    // Step 2: Add all deletions to the batch

    // 2.1: Delete payments
    for (final doc in paymentsQuery.docs) {
      batch.delete(doc.reference);
      operationCount++;
      await commitBatchIfNeeded();
    }

    // 2.2: Delete claimed tickets
    for (final doc in claimedTicketsQuery.docs) {
      batch.delete(doc.reference);
      operationCount++;
      await commitBatchIfNeeded();
    }

    // 2.3: Delete applications
    for (final doc in applicationsQuery.docs) {
      batch.delete(doc.reference);
      operationCount++;
      await commitBatchIfNeeded();
    }

    // 2.4: Finally, delete the event itself
    final DocumentReference eventRef = _firestore.collection('events').doc(eventId);
    batch.delete(eventRef);
    operationCount++;

    // Step 3: Commit the final batch
    if (operationCount > 0) {
      print("  - Committing final batch with $operationCount operations");
      await batch.commit();
    }

    // Log the successful deletion
    print("✓ Successfully deleted event '$eventName' and all related records");
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.getCurrentUser();
    return WillPopScope(
        onWillPop: () async {
          final shouldExit = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Exit App'),
              content: Text('Do you really want to exit the app?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Yes'),
                ),
              ],
            ),
          );
          return shouldExit ?? false;
        },

      child: Scaffold(
        appBar: AppBar(
          title: Text('Events'),
          actions: [
            // Add a refresh button to manually trigger cleanup
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _isProcessingDeletion ? null : _runExpiredEventsCleanup,
              tooltip: 'Check for expired events',
            ),
            IconButton(
              icon: Icon(Icons.search),
              onPressed: () async {
                final String? searchTerm = await showSearch<String>(
                  context: context,
                  delegate: EventSearchDelegate(_firestore),
                );
                if (searchTerm != null) {
                  print('Searched for: $searchTerm');
                }
              },
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
                child: Text(
                  'Event Collab',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.home),
                title: Text('Home'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: Icon(Icons.smart_toy),
                title: Text('AI Assistant'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AiChatbotScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.account_circle),
                title: Text('My Profile'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ProfilePage()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.logout),
                title: Text('Logout'),
                onTap: () async {
                  final shouldLogout = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Logout'),
                      content: Text('Do you really want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text('No'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text('Yes'),
                        ),
                      ],
                    ),
                  );

                  if (shouldLogout ?? false) {
                    await _authService.signOut();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => AuthScreen()),
                          (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // Show loading indicator when processing deletions
            if (_isProcessingDeletion)
              Container(
                padding: EdgeInsets.symmetric(vertical: 2),
                color: Colors.amber[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text("Checking for expired events...", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getEventsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading events: ${snapshot.error}'));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final events = snapshot.data?.docs ?? [];

                  if (events.isEmpty) {
                    return Center(child: Text('No events available'));
                  }

                  final eventMaps = events.map((d) => d.data() as Map<String, dynamic>).toList();

                  return ListView.builder(
                    padding: EdgeInsets.all(8),
                    itemCount: events.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildAiRecommendationsCard(context, eventMaps);
                      }
                      final event = events[index - 1].data() as Map<String, dynamic>;
                      final documentId = events[index - 1].id;

                      return EventCard(
                        event: event,
                        documentId: documentId,
                        onTap: () {
                          // Let the EventCard handle navigation
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getEventsStream() {
    // Calculate start of today for proper filtering
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return _firestore.collection('events')
    // Show events that end today or later
        .where('endDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .orderBy('endDate')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _fetchAiRecommendations(List<Map<String, dynamic>> events) async {
    if (huggingFaceApiToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add HF_TOKEN to get AI recommendations')),
      );
      return;
    }
    setState(() => _aiRecommendationsLoading = true);
    String? userRole;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        userRole = doc.data()?['role'];
      }
    } catch (_) {}
    final service = HuggingFaceService(apiToken: huggingFaceApiToken);
    final result = await service.getEventRecommendations(
      availableEvents: events,
      userRole: userRole,
    );
    service.dispose();
    if (mounted) {
      setState(() {
        _aiRecommendationsLoading = false;
        _aiRecommendationsText = result;
      });
    }
  }

  Widget _buildAiRecommendationsCard(BuildContext context, List<Map<String, dynamic>> events) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _aiRecommendationsExpanded = !_aiRecommendationsExpanded);
          if (_aiRecommendationsExpanded && _aiRecommendationsText == null && !_aiRecommendationsLoading) {
            _fetchAiRecommendations(events);
          }
        },
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.purple[700], size: 24),
                  SizedBox(width: 8),
                  Text(
                    'AI Event Recommendations',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.purple[700],
                    ),
                  ),
                  Spacer(),
                  Icon(
                    _aiRecommendationsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
              if (_aiRecommendationsExpanded) ...[
                SizedBox(height: 12),
                if (_aiRecommendationsLoading)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text('Getting recommendations...', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  )
                else if (_aiRecommendationsText != null)
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _aiRecommendationsText!,
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                  )
                else if (huggingFaceApiToken.isEmpty)
                  Text(
                    'Add HF_TOKEN (--dart-define=HF_TOKEN=xxx) for AI recommendations.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  )
                else
                  Text(
                    'Tap to load recommendations',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EventSearchDelegate extends SearchDelegate<String> {
  final FirebaseFirestore firestore;

  EventSearchDelegate(this.firestore);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Start typing to search events',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Search by event name, location, description, or roles',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    // Convert query to lowercase for case-insensitive search
    final searchTerm = query.toLowerCase();

    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('events').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading events: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data?.docs ?? [];

        // Filter events locally to allow for more complex searches
        final filteredEvents = events.where((doc) {
          final event = doc.data() as Map<String, dynamic>;

          // Check each field for matches (case-insensitive)
          final name = event['name']?.toString().toLowerCase() ?? '';
          final description = event['description']?.toString().toLowerCase() ?? '';
          final location = event['location']?.toString().toLowerCase() ?? '';
          final type = event['type']?.toString().toLowerCase() ?? '';

          // Check lookingFor roles
          bool roleMatch = false;
          if (event['lookingFor'] is List) {
            final lookingForRoles = (event['lookingFor'] as List)
                .where((item) => item != null)
                .map((item) => item.toString().toLowerCase())
                .toList();

            // Check if any role matches the search term
            roleMatch = lookingForRoles.any((role) => role.contains(searchTerm));
          }

          return name.contains(searchTerm) ||
              description.contains(searchTerm) ||
              location.contains(searchTerm) ||
              type.contains(searchTerm) ||
              roleMatch;
        }).toList();

        if (filteredEvents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text(
                  'No events found for "$query"',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  'Try different keywords or check your spelling',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredEvents.length,
          itemBuilder: (context, index) {
            final event = filteredEvents[index].data() as Map<String, dynamic>;
            final documentId = filteredEvents[index].id;

            // Get the lookingFor list from the event data
            final List<String> lookingFor = [];
            if (event['lookingFor'] is List) {
              lookingFor.addAll(
                  (event['lookingFor'] as List)
                      .where((item) => item != null)
                      .map((item) => item.toString())
                      .toList()
              );
            }

            return Card(
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.all(8),
                leading: event['bannerImage'] != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    event['bannerImage'],
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey[200],
                      child: Icon(Icons.event, color: Colors.grey[400]),
                    ),
                  ),
                )
                    : Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[200],
                  child: Icon(Icons.event, color: Colors.grey[400]),
                ),
                title: Text(
                  event['name'] ?? 'No title',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event['description'] != null)
                      Text(
                        event['description']!.length > 50
                            ? '${event['description']!.substring(0, 50)}...'
                            : event['description']!,
                      ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          event['type'] == 'online'
                              ? 'Online Event'
                              : event['location'] ?? '',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),

                    // Display "Looking For" tags if they exist
                    if (lookingFor.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Looking for: ',
                            style: TextStyle(
                              color: Colors.purple[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: lookingFor.map((role) {
                                  return Container(
                                    margin: EdgeInsets.only(right: 4),
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      role,
                                      style: TextStyle(
                                        color: Colors.purple[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                onTap: () {
                  close(context, event['name'] ?? '');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => EventDetailPage(eventId: documentId),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final String documentId;
  final VoidCallback onTap;

  const EventCard({
    required this.event,
    required this.documentId,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  String _truncateDescription(String desc) {
    final words = desc.split(' ');
    if (words.length <= 20) return desc;
    return words.take(20).join(' ') + '...';
  }

  @override
  Widget build(BuildContext context) {
    // Get the lookingFor list from the event data
    final List<String> lookingFor = [];
    if (event['lookingFor'] is List) {
      // Make sure each item is converted to String safely
      lookingFor.addAll(
          (event['lookingFor'] as List)
              .where((item) => item != null)
              .map((item) => item.toString())
              .toList()
      );
    }

    // Check if the event has free tickets
    // First check the explicit field, then fall back to price check
    final bool isFreeTicket =
    (event['isFreeTicket'] is bool) ? event['isFreeTicket'] :
    ((event['ticketPrice'] is num) ? event['ticketPrice'] == 0 : false);

    // Get seat count (previously tickets)
    final int totalTickets = (event['totalTickets'] is num) ? event['totalTickets'] :
    ((event['totalTickets'] is num) ? event['totalTickets'] : 0);

    // Safe navigation method
    void navigateToEventDetails() {
      try {
        print("Navigating to event with ID: $documentId");
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => EventDetailPage(eventId: documentId),
          ),
        );
      } catch (e) {
        print("Navigation error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open event details: $e")),
        );
      }
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: navigateToEventDetails, // Use our safe navigation method
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner Image with FREE badge overlay
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  // Image takes full width
                  Container(
                    width: double.infinity, // Force full width
                    height: 150,
                    child: event['bannerImage'] != null
                        ? Image.network(
                      event['bannerImage'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.image, size: 50),
                      ),
                    )
                        : Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.image, size: 50),
                    ),
                  ),
                  // Free ticket badge
                  if (isFreeTicket)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'FREE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Name
                  Text(
                    event['name'] ?? 'No title',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),

                  // Location or Online - FIXED to handle null location safely
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        event['type'] == 'onsite'
                            ? (event['location'] != null ? event['location'].toString() : 'Location not specified')
                            : 'Online',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),

                  // Available Total Tickets
                  Row(
                    children: [
                      Icon(Icons.event_seat, size: 16, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        'Total Tickets: $totalTickets',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),

                  // Price information
                  Row(
                    children: [
                      Icon(Icons.payments, size: 16, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        isFreeTicket
                            ? 'Free Entry'
                            : 'Price: ${(event['ticketPrice'] is num) ? '${event['ticketPrice']} PKR' : 'Price unavailable'}',
                        style: TextStyle(
                          color: isFreeTicket ? Colors.green[700] : Colors.grey[600],
                          fontWeight: isFreeTicket ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // Truncated Description
                  Text(
                    _truncateDescription(event['description'] ?? 'No description'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Display "Looking For" tags if they exist
                  if (lookingFor.isNotEmpty) SizedBox(height: 8),
                  if (lookingFor.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(
                      'Looking For:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[700],
                      ),
                    ),
                    SizedBox(height: 4),
                    Wrap(
                      spacing: 4.0,
                      runSpacing: 4.0,
                      children: lookingFor.map((item) {
                        return Chip(
                          label: Text(item),
                          backgroundColor: Colors.purple[50],
                          labelStyle: TextStyle(
                            color: Colors.purple[700],
                            fontSize: 12,
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    )
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}