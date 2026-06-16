import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// state code → (display name, [cities])
const _kLocations = <String, (String, List<String>)>{
  // India
  'IN-KA': ('Karnataka', ['Bangalore', 'Mysore', 'Hubli', 'Mangalore', 'Belgaum']),
  'IN-MH': ('Maharashtra', ['Mumbai', 'Pune', 'Nagpur', 'Nashik', 'Aurangabad']),
  'IN-TN': ('Tamil Nadu', ['Chennai', 'Coimbatore', 'Madurai', 'Salem', 'Tiruchirappalli']),
  'IN-DL': ('Delhi', ['New Delhi', 'Dwarka', 'Rohini', 'Noida', 'Gurugram']),
  'IN-UP': ('Uttar Pradesh', ['Lucknow', 'Kanpur', 'Agra', 'Varanasi', 'Prayagraj']),
  'IN-RJ': ('Rajasthan', ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota', 'Ajmer']),
  'IN-GJ': ('Gujarat', ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Gandhinagar']),
  'IN-WB': ('West Bengal', ['Kolkata', 'Howrah', 'Durgapur', 'Asansol', 'Siliguri']),
  'IN-TS': ('Telangana', ['Hyderabad', 'Warangal', 'Nizamabad', 'Karimnagar']),
  'IN-AP': ('Andhra Pradesh', ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Tirupati']),
  'IN-KL': ('Kerala', ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur']),
  'IN-PB': ('Punjab', ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala']),
  'IN-HR': ('Haryana', ['Faridabad', 'Gurugram', 'Panipat', 'Ambala', 'Rohtak']),
  'IN-BR': ('Bihar', ['Patna', 'Gaya', 'Muzaffarpur', 'Bhagalpur']),
  'IN-MP': ('Madhya Pradesh', ['Bhopal', 'Indore', 'Gwalior', 'Jabalpur']),
  // United States
  'US-CA': ('California', ['San Francisco', 'Los Angeles', 'San Diego', 'Fremont', 'San Jose', 'Livermore', 'San Ramon', 'Sunnyvale']),
  'US-TX': ('Texas', ['Houston', 'Dallas', 'Austin', 'San Antonio', 'Frisco', 'Irving']),
  'US-NY': ('New York', ['New York City', 'Buffalo', 'Rochester', 'Albany', 'Yonkers']),
  'US-NJ': ('New Jersey', ['Newark', 'Jersey City', 'Edison', 'Parsippany', 'Princeton']),
  'US-IL': ('Illinois', ['Chicago', 'Aurora', 'Naperville', 'Joliet', 'Rockford']),
  'US-FL': ('Florida', ['Miami', 'Orlando', 'Tampa', 'Jacksonville', 'Gainesville']),
  'US-GA': ('Georgia', ['Atlanta', 'Augusta', 'Columbus', 'Savannah', 'Athens']),
  'US-WA': ('Washington', ['Seattle', 'Spokane', 'Tacoma', 'Bellevue', 'Redmond']),
  'US-VA': ('Virginia', ['Virginia Beach', 'Norfolk', 'Arlington', 'Richmond', 'Herndon']),
  'US-MD': ('Maryland', ['Baltimore', 'Frederick', 'Rockville', 'Gaithersburg']),
  // Australia
  'AU-NSW': ('New South Wales', ['Sydney', 'Newcastle', 'Wollongong', 'Parramatta']),
  'AU-VIC': ('Victoria', ['Melbourne', 'Geelong', 'Ballarat', 'Bendigo']),
  'AU-QLD': ('Queensland', ['Brisbane', 'Gold Coast', 'Sunshine Coast', 'Townsville']),
  'AU-WA':  ('Western Australia', ['Perth', 'Fremantle', 'Bunbury', 'Geraldton']),
  'AU-SA':  ('South Australia', ['Adelaide', 'Mount Gambier', 'Whyalla']),
  // United Kingdom
  'GB-ENG': ('England', ['London', 'Birmingham', 'Manchester', 'Leeds', 'Sheffield', 'Leicester', 'Coventry']),
  'GB-SCT': ('Scotland', ['Glasgow', 'Edinburgh', 'Aberdeen', 'Dundee']),
  'GB-WLS': ('Wales', ['Cardiff', 'Swansea', 'Newport', 'Wrexham']),
  // Canada
  'CA-ON': ('Ontario', ['Toronto', 'Ottawa', 'Mississauga', 'Brampton', 'Hamilton']),
  'CA-BC': ('British Columbia', ['Vancouver', 'Surrey', 'Burnaby', 'Richmond']),
  'CA-AB': ('Alberta', ['Calgary', 'Edmonton', 'Red Deer', 'Lethbridge']),
  // UAE
  'AE-DU': ('Dubai', ['Dubai']),
  'AE-AB': ('Abu Dhabi', ['Abu Dhabi', 'Al Ain']),
  'AE-SH': ('Sharjah', ['Sharjah']),
};

// country code → state codes
const _kCountryStates = <String, List<String>>{
  'IN': ['IN-KA','IN-MH','IN-TN','IN-DL','IN-UP','IN-RJ','IN-GJ','IN-WB','IN-TS','IN-AP','IN-KL','IN-PB','IN-HR','IN-BR','IN-MP'],
  'US': ['US-CA','US-TX','US-NY','US-NJ','US-IL','US-FL','US-GA','US-WA','US-VA','US-MD'],
  'AU': ['AU-NSW','AU-VIC','AU-QLD','AU-WA','AU-SA'],
  'GB': ['GB-ENG','GB-SCT','GB-WLS'],
  'CA': ['CA-ON','CA-BC','CA-AB'],
  'AE': ['AE-DU','AE-AB','AE-SH'],
};

String stateName(String code) => _kLocations[code]?.$1 ?? code;
List<String> stateCities(String code) => _kLocations[code]?.$2 ?? [];
List<String> statesForCountry(String country) => _kCountryStates[country] ?? [];

class LocationPickerSheet extends StatefulWidget {
  final String? country;
  final String? initialState;
  const LocationPickerSheet({super.key, this.country, this.initialState});

  @override State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  String? _selectedState;
  String _query = '';

  @override void initState() {
    super.initState();
    _selectedState = widget.initialState;
  }

  List<String> get _states => statesForCountry(widget.country ?? '');

  @override Widget build(BuildContext context) {
    final pickingCity = _selectedState != null;
    final cities = pickingCity ? stateCities(_selectedState!) : <String>[];
    final filteredCities = _query.isEmpty
        ? cities
        : cities.where((c) => c.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          // Header with back button when picking city
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (pickingCity) ...[
                GestureDetector(
                  onTap: () => setState(() { _selectedState = null; _query = ''; }),
                  child: const Icon(Icons.arrow_back_ios, size: 18, color: AppColors.text2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  pickingCity ? 'Select city in ${stateName(_selectedState!)}' : 'Select state',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
              ),
            ]),
          ),
          if (pickingCity) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                autofocus: false,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  hintText: 'Search city...',
                  prefixIcon: Icon(Icons.search, color: AppColors.text2),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ] else
            const SizedBox(height: 8),
          Expanded(
            child: pickingCity
              ? ListView.builder(
                  controller: controller,
                  itemCount: filteredCities.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.location_city, color: AppColors.text2, size: 20),
                    title: Text(filteredCities[i], style: const TextStyle(color: AppColors.text)),
                    onTap: () => Navigator.pop(context, (_selectedState!, filteredCities[i])),
                  ),
                )
              : ListView.builder(
                  controller: controller,
                  itemCount: _states.length,
                  itemBuilder: (_, i) {
                    final code = _states[i];
                    return ListTile(
                      leading: const Icon(Icons.map_outlined, color: AppColors.text2, size: 20),
                      title: Text(stateName(code), style: const TextStyle(color: AppColors.text)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.text2, size: 18),
                      onTap: () => setState(() { _selectedState = code; _query = ''; }),
                    );
                  },
                ),
          ),
          const SafeArea(child: SizedBox(height: 8)),
        ]),
      ),
    );
  }
}
