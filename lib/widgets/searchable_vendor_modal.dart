import 'package:flutter/material.dart';

/// Senior Lead Enterprise Searchable Vendor Selector Modal.
/// Provides a bottom sheet / adaptive modal dialog with live real-time search,
/// pinned sticky search bar, "All Vendors" selection, smooth animations,
/// and fast keyboard interaction.
class SearchableVendorModal extends StatefulWidget {
  final List<String> allVendors;
  final String? selectedVendor;
  final String title;
  final String allOptionLabel;

  const SearchableVendorModal({
    super.key,
    required this.allVendors,
    this.selectedVendor,
    this.title = "Select Vendor",
    this.allOptionLabel = "All Vendors",
  });

  /// Static helper to display the modal bottom sheet adaptively
  static Future<String?> show(
    BuildContext context, {
    required List<String> allVendors,
    String? selectedVendor,
    String title = "Select Vendor",
    String allOptionLabel = "All Vendors",
  }) {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SearchableVendorModal(
        allVendors: allVendors,
        selectedVendor: selectedVendor,
        title: title,
        allOptionLabel: allOptionLabel,
      ),
    );
  }

  @override
  State<SearchableVendorModal> createState() => _SearchableVendorModalState();
}

class _SearchableVendorModalState extends State<SearchableVendorModal> {
  static const Color primaryRed = Color(0xFFD71920);

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  List<String> _uniqueVendors = [];

  @override
  void initState() {
    super.initState();
    _uniqueVendors = widget.allVendors
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _searchCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _query = _searchCtrl.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final query = _query.trim().toLowerCase();

    final filteredVendors = query.isEmpty
        ? _uniqueVendors
        : _uniqueVendors
            .where((v) => v.toLowerCase().contains(query))
            .toList();

    final bool isAllSelected =
        widget.selectedVendor == null || widget.selectedVendor!.isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.80,
              minHeight: screenHeight * 0.40,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 20,
                  offset: Offset(0, -4),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag pill
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header Row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: primaryRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              "${_uniqueVendors.length} registered vendors",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF6B7280)),
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // Pinned Search TextField
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF111827)),
                      decoration: InputDecoration(
                        hintText: "Search vendor name...",
                        hintStyle: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: primaryRed, size: 20),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    size: 18, color: Color(0xFF9CA3AF)),
                                onPressed: () {
                                  _searchCtrl.clear();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // "All Vendors" option pinned at top when search is empty or matches
                if (_query.isEmpty) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Material(
                      color: isAllSelected
                          ? const Color(0xFFFEF2F2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.of(context).pop(''); // '' represents All
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isAllSelected
                                      ? primaryRed.withValues(alpha: 0.12)
                                      : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.groups_outlined,
                                  size: 18,
                                  color: isAllSelected
                                      ? primaryRed
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "${widget.allOptionLabel} (Show All)",
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isAllSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: isAllSelected
                                        ? primaryRed
                                        : const Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                              if (isAllSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: primaryRed,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 8, indent: 16, endIndent: 16),
                ],

                // Live filtered list of vendors
                Expanded(
                  child: filteredVendors.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: filteredVendors.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: Color(0xFFF3F4F6)),
                          itemBuilder: (context, index) {
                            final vendor = filteredVendors[index];
                            final isSelected = widget.selectedVendor == vendor;

                            return Material(
                              color: isSelected
                                  ? const Color(0xFFFEF2F2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  Navigator.of(context).pop(vendor);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 11),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 15,
                                        backgroundColor: isSelected
                                            ? primaryRed
                                                .withValues(alpha: 0.15)
                                            : Colors.grey.shade100,
                                        child: Text(
                                          vendor.isNotEmpty
                                              ? vendor[0].toUpperCase()
                                              : 'V',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? primaryRed
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          vendor,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? primaryRed
                                                : const Color(0xFF111827),
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: primaryRed,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "No vendors found matching '$_query'",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Check for spelling or try a different keyword.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text("Clear Search"),
              style: TextButton.styleFrom(foregroundColor: primaryRed),
              onPressed: () {
                _searchCtrl.clear();
              },
            ),
          ],
        ),
      ),
    );
  }
}
