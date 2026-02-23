import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../cloudinary_service.dart';
import 'package:intl/intl.dart';
import 'package:event_collab/screens/home_screen.dart';
import 'package:event_collab/config/api_config.dart';
import 'package:event_collab/services/huggingface_service.dart';

class AddEventPage extends StatefulWidget {
  final String? eventId;
  final Map<String, dynamic>? initialEventData;

  const AddEventPage({
    Key? key,
    this.eventId,
    this.initialEventData,
  }) : super(key: key);

  @override
  _AddEventPageState createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ImagePicker _picker = ImagePicker();

  // Form fields
  String _eventName = '';
  String _description = '';
  File? _bannerImage;
  String _eventType = 'online';
  String? _location;
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _dateFormat = 'yyyy-MM-dd'; // Specify your preferred date format
  String _timeFormat = 'HH:mm';     // Specify your preferred time format
  int _totalTickets = 0;
  bool _isFreeTicket = false;  // New field to determine if ticket is free
  double _ticketPrice = 0.0;
  List<String> _lookingFor = [];
  String? _existingImageUrl;
  List<String> _accountNumbers = [];
  List<String> _bankNames = [""];
  bool _showAccountField = false;
  // Options for dropdowns
  final List<String> _eventTypeOptions = ['online', 'onsite'];
  final List<String> _lookingForOptions = ['Sponsor', 'Vendor', 'Volunteer'];

  bool _isLoading = false;
  bool _isGeneratingDescription = false;

  @override
  void initState() {
    super.initState();
    _cloudinaryService.initialize();

    if (widget.initialEventData != null) {
      _eventName = widget.initialEventData!['name'] ?? '';
      _description = widget.initialEventData!['description'] ?? '';
      _descriptionController.text = _description;
      _eventType = widget.initialEventData!['type'] ?? 'online';
      _location = widget.initialEventData!['location'];
      _totalTickets = widget.initialEventData!['totalTickets'] ?? 0;
      _ticketPrice = widget.initialEventData!['ticketPrice']?.toDouble() ?? 0.0;
      _isFreeTicket = (_ticketPrice == 0.0);
      _accountNumbers = List<String>.from(widget.initialEventData!['accountNumbers'] ?? []);
      _bankNames = List<String>.from(widget.initialEventData!['bankNames'] ?? [""]);
      _showAccountField = !_isFreeTicket && _accountNumbers.isEmpty;
      _lookingFor = List<String>.from(widget.initialEventData!['lookingFor'] ?? []);
      _existingImageUrl = widget.initialEventData!['bannerImage'];
      if (widget.initialEventData!['startDate'] != null) {
        _startDate = (widget.initialEventData!['startDate'] as Timestamp).toDate();
      }
      if (widget.initialEventData!['endDate'] != null) {
        _endDate = (widget.initialEventData!['endDate'] as Timestamp).toDate();
      }
      // For times, you might need to adjust based on how you store them
      // This assumes you store them as strings in 'HH:mm' format
      if (widget.initialEventData!['startTime'] != null) {
        final parts = widget.initialEventData!['startTime'].split(':');
        _startTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
      if (widget.initialEventData!['endTime'] != null) {
        final parts = widget.initialEventData!['endTime'].split(':');
        _endTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _generateAiDescription() async {
    if (huggingFaceApiToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add HF_TOKEN for AI description. Run with --dart-define=HF_TOKEN=your_token')),
      );
      return;
    }
    if (_eventName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter event name first')),
      );
      return;
    }
    setState(() => _isGeneratingDescription = true);
    final service = HuggingFaceService(apiToken: huggingFaceApiToken);
    final result = await service.generateEventDescription(
      eventName: _eventName,
      eventType: _eventType,
      location: _eventType == 'onsite' ? _location : null,
      lookingFor: _lookingFor.isNotEmpty ? _lookingFor : null,
    );
    service.dispose();
    if (mounted) {
      setState(() => _isGeneratingDescription = false);
      if (result != null && result.isNotEmpty) {
        _descriptionController.text = result;
        _description = result;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate. Model may be loading. Try again.')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _bannerImage = File(pickedFile.path);
          _existingImageUrl = null; // Clear existing URL if new image is selected
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
    }
  }


  Future<void> _addEvent() async {
    if (!_formKey.currentState!.validate()) return;

    // Add this validation check for payment methods
    if (!_isFreeTicket && (_accountNumbers.isEmpty || _accountNumbers[0].isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('At least one payment method is required')),
      );
      return;
    }

    if (_bannerImage == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a banner image')),
      );
      return;
    }

    // Add this validation check before setting _isLoading to true
    if (_startDate == null || _endDate == null || _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select all date and time fields')),
      );
      return;
    }

    // Also validate that end date/time is after start date/time
    final startDateTime = DateTime(
      _startDate!.year, _startDate!.month, _startDate!.day,
      _startTime!.hour, _startTime!.minute,
    );
    final endDateTime = DateTime(
      _endDate!.year, _endDate!.month, _endDate!.day,
      _endTime!.hour, _endTime!.minute,
    );

    if (endDateTime.isBefore(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('End date/time must be after start date/time')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      _formKey.currentState!.save();

      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      Map<String, dynamic> eventData = {
        'name': _eventName,
        'description': _description,
        'type': _eventType,
        'location': _eventType == 'onsite' ? _location : null,
        'startDate': _startDate != null ? Timestamp.fromDate(_startDate!) : null,
        'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
        'startTime': _startTime != null
            ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'endTime': _endTime != null
            ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'totalTickets': _totalTickets,
        'isFreeTicket': _isFreeTicket,
        'ticketPrice': _isFreeTicket ? 0.0 : _ticketPrice,
        'accountNumbers': _accountNumbers,
        'bankNames': _bankNames,
        'lookingFor': _lookingFor,
        'organizerId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Handle image upload or use existing URL
      if (_bannerImage != null) {
        final imageUrl = await _cloudinaryService.uploadImage(_bannerImage!);
        if (imageUrl == null) throw Exception('Failed to upload image');
        eventData['bannerImage'] = imageUrl;
      } else if (_existingImageUrl != null) {
        eventData['bannerImage'] = _existingImageUrl;
      }

      if (widget.eventId != null) {
        // Get the current event data to find any changes that need to be propagated
        DocumentSnapshot eventSnapshot = await _firestore.collection('events').doc(widget.eventId).get();
        Map<String, dynamic> currentEventData = eventSnapshot.data() as Map<String, dynamic>;

        // Check if name has changed
        String oldEventName = currentEventData['name'] ?? '';
        bool nameChanged = oldEventName != _eventName;

        // Update existing event
        await _firestore.collection('events').doc(widget.eventId).update(eventData);

        // If name has changed, update all related collections
        if (nameChanged) {
          await _updateEventNameInOtherCollections(widget.eventId!, oldEventName, _eventName);
        }
      } else {
        // Create new event
        eventData['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('events').add(eventData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.eventId != null ? 'Event updated successfully!' : 'Event added successfully!'),
          duration: Duration(seconds: 4),
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
            (Route<dynamic> route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ${widget.eventId != null ? 'update' : 'add'} event: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

// New method to update event name in other collections
  Future<void> _updateEventNameInOtherCollections(String eventId, String oldName, String newName) async {
    // List of collections where the event name needs to be updated
    List<String> collectionsToUpdate = [
      'claimed_tickets',
      'payments',
      'email_logs',
      'event_applications'
    ];

    // Update each collection
    for (String collection in collectionsToUpdate) {
      // Get documents related to this event
      QuerySnapshot querySnapshot = await _firestore
          .collection(collection)
          .where('eventId', isEqualTo: eventId)
          .get();

      // Batch update for better performance
      WriteBatch batch = _firestore.batch();
      bool batchHasOperations = false;

      for (QueryDocumentSnapshot doc in querySnapshot.docs) {
        // Update document with new event name
        batch.update(doc.reference, {'eventName': newName});
        batchHasOperations = true;
      }

      // Commit the batch if there are operations
      if (batchHasOperations) {
        await batch.commit();
      }
    }

    print('Updated event name from "$oldName" to "$newName" in all related collections');
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _startDate) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now().add(Duration(days: 1))),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _endDate) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _startTime) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _endTime) {
      setState(() => _endTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventId != null ? 'Edit Event' : 'Add New Event'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner Image
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _bannerImage != null
                      ? Image.file(_bannerImage!, fit: BoxFit.cover)
                      : _existingImageUrl != null
                      ? Image.network(_existingImageUrl!, fit: BoxFit.cover)
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate,
                          size: 50, color: Colors.grey[500]),
                      SizedBox(height: 8),
                      Text('Tap to add banner image',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
              if (_existingImageUrl != null || _bannerImage != null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap image to change',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(height: 16),

              // Event Name
              TextFormField(
                initialValue: _eventName,
                decoration: InputDecoration(
                  labelText: 'Event Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter event name';
                  }
                  return null;
                },
                onSaved: (value) => _eventName = value!,
              ),
              SizedBox(height: 16),

              // Description with AI generate
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter description';
                        }
                        return null;
                      },
                      onSaved: (value) => _description = value ?? _descriptionController.text,
                    ),
                  ),
                  SizedBox(width: 8),
                  Column(
                    children: [
                      IconButton(
                        onPressed: _isGeneratingDescription ? null : _generateAiDescription,
                        icon: _isGeneratingDescription
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.auto_awesome),
                        tooltip: 'Generate with AI',
                        color: Colors.purple[700],
                      ),
                      Text(
                        'AI',
                        style: TextStyle(fontSize: 10, color: Colors.purple[700]),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16),

              // Event Type
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Event Type',
                  border: OutlineInputBorder(),
                ),
                value: _eventType,
                items: _eventTypeOptions.map((type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type[0].toUpperCase() + type.substring(1)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _eventType = value!;
                  });
                },
              ),
              SizedBox(height: 16),

              // Location (only shown for onsite events)
              if (_eventType == 'onsite')
                TextFormField(
                  initialValue: _location,
                  decoration: InputDecoration(
                    labelText: 'Choose Location',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.location_on),
                  ),
                  validator: (value) {
                    if (_eventType == 'onsite' && (value == null || value.isEmpty)) {
                      return 'Please enter location';
                    }
                    return null;
                  },
                  onSaved: (value) => _location = value,
                ),
              if (_eventType == 'onsite') SizedBox(height: 16),

              TextFormField(
                initialValue: _totalTickets.toString(),
                decoration: InputDecoration(
                  labelText: 'Total Tickets',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter total tickets';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
                onSaved: (value) => _totalTickets = int.parse(value!),
              ),
              SizedBox(height: 16),

              ListTile(
                title: Text('Start Date'),
                subtitle: Text(_startDate != null
                    ? DateFormat(_dateFormat).format(_startDate!)
                    : 'Select start date'),
                trailing: Icon(Icons.calendar_today),
                onTap: () => _selectStartDate(context),
              ),
              SizedBox(height: 8),

              ListTile(
                title: Text('Start Time'),
                subtitle: Text(_startTime != null
                    ? _startTime!.format(context)
                    : 'Select start time'),
                trailing: Icon(Icons.access_time),
                onTap: () => _selectStartTime(context),
              ),
              SizedBox(height: 16),

              ListTile(
                title: Text('End Date'),
                subtitle: Text(_endDate != null
                    ? DateFormat(_dateFormat).format(_endDate!)
                    : 'Select end date'),
                trailing: Icon(Icons.calendar_today),
                onTap: () => _selectEndDate(context),
              ),
              SizedBox(height: 8),

              ListTile(
                title: Text('End Time'),
                subtitle: Text(_endTime != null
                    ? _endTime!.format(context)
                    : 'Select end time'),
                trailing: Icon(Icons.access_time),
                onTap: () => _selectEndTime(context),
              ),
              SizedBox(height: 16),

              // Free Ticket Toggle
              SwitchListTile(
                title: Text('Pricing'),
                subtitle: Text(_isFreeTicket ? 'Tickets are free' : 'Tickets are paid'),
                value: _isFreeTicket,
                activeColor: Theme.of(context).primaryColor,
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey),
                ),
                onChanged: (bool value) {
                  setState(() {
                    _isFreeTicket = value;
                    _showAccountField = !value;
                    if (_isFreeTicket) {
                      _ticketPrice = 0.0;
                      _accountNumbers.clear();
                    }
                  });
                },
              ),
              SizedBox(height: 16),

// Ticket Price (only shown if not free)
              if (!_isFreeTicket)
                TextFormField(
                  initialValue: _ticketPrice.toString(),
                  decoration: InputDecoration(
                    labelText: 'Ticket Price',
                    border: OutlineInputBorder(),
                    suffixText: 'PKR',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (!_isFreeTicket && (value == null || value.isEmpty)) {
                      return 'Please enter ticket price';
                    }
                    if (!_isFreeTicket && double.tryParse(value!) == null) {
                      return 'Please enter a valid price';
                    }
                    return null;
                  },
                  onSaved: (value) => _ticketPrice = _isFreeTicket ? 0.0 : double.parse(value!),
                ),

              // Replace your current account numbers section with this:
              if (!_isFreeTicket) ...[
                Text(
                  'Payment Accounts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                if (_accountNumbers.isEmpty)
                  Text(
                    'At least one payment method is required',
                    style: TextStyle(color: Colors.red),
                  ),
                ..._accountNumbers.asMap().entries.map((entry) {
                  int index = entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: _bankNames.length > index ? _bankNames[index] : '',
                                decoration: InputDecoration(
                                  labelText: 'Bank Name ${index + 1}',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter bank name';
                                  }
                                  return null;
                                },
                                onChanged: (value) {
                                  setState(() {
                                    if (_bankNames.length > index) {
                                      _bankNames[index] = value;
                                    } else {
                                      _bankNames.add(value);
                                    }
                                  });
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                initialValue: entry.value,
                                decoration: InputDecoration(
                                  labelText: 'Account/IBAN No. ${index + 1}',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter account/IBAN number';
                                  }
                                  return null;
                                },
                                onChanged: (value) {
                                  setState(() {
                                    _accountNumbers[index] = value;
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _accountNumbers.removeAt(index);
                                  if (_bankNames.length > index) {
                                    _bankNames.removeAt(index);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                      ],
                    ),
                  );
                }).toList(),

                // Add new account field button
                TextButton(
                  onPressed: () {
                    setState(() {
                      _accountNumbers.add("");
                      _bankNames.add("");
                    });
                  },
                  child: Text('+ Add Another Account'),
                ),
                SizedBox(height: 16),
              ],
              // I'm looking for (multi-select dropdown)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: "I'm looking for: (Optional)",
                  border: OutlineInputBorder(),
                ),
                child: Wrap(
                  spacing: 8.0,
                  children: _lookingForOptions.map((option) {
                    return FilterChip(
                      label: Text(option),
                      selected: _lookingFor.contains(option),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _lookingFor.add(option);
                          } else {
                            _lookingFor.remove(option);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addEvent,
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(widget.eventId != null ? 'Update Event' : 'Add Event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}