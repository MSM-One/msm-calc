import 'package:flutter/material.dart';

/// Reusable Real-time Vendor Search & Autocomplete Dropdown component.
/// Displays existing vendor matches with case-insensitive fuzzy substring search,
/// or an option to create a new vendor when no exact match exists.
class VendorSearchAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final List<dynamic> existingVendors;
  final ValueChanged<String>? onVendorSelected;
  final String labelText;
  final String? Function(String?)? validator;

  const VendorSearchAutocomplete({
    super.key,
    required this.controller,
    required this.existingVendors,
    this.onVendorSelected,
    this.labelText = "Vendor Name",
    this.validator,
  });

  @override
  State<VendorSearchAutocomplete> createState() =>
      _VendorSearchAutocompleteState();
}

class _VendorSearchAutocompleteState extends State<VendorSearchAutocomplete> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryRed = Color(0xFFD71920);

    // Extract non-empty vendor names & sort alphabetically
    final Set<String> seen = {};
    final List<String> vendorsList = [];
    for (final v in widget.existingVendors) {
      String name = '';
      if (v is Map) {
        name = (v['name'] ??
                v['vendor_name'] ??
                v['party_name'] ??
                v['party'] ??
                '')
            .toString()
            .trim();
      } else if (v != null) {
        name = v.toString().trim();
      }
      if (name.isNotEmpty && seen.add(name.toUpperCase())) {
        vendorsList.add(name.toUpperCase());
      }
    }
    vendorsList.sort();

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text;
        final q = query.trim().toLowerCase();
        if (q.isEmpty) {
          return vendorsList;
        }

        // Case-Insensitive Substring Match against all vendor records
        final matches = vendorsList.where((v) {
          return v.toLowerCase().contains(q);
        }).toList();

        final hasExactMatch = vendorsList.any(
          (v) => v.toLowerCase() == q,
        );

        if (!hasExactMatch && query.trim().isNotEmpty) {
          matches.add("+ Add new vendor '${query.trim()}'");
        }

        return matches;
      },
      onSelected: (String selection) {
        if (selection.startsWith("+ Add new vendor '") &&
            selection.endsWith("'")) {
          final newName = selection
              .substring("+ Add new vendor '".length, selection.length - 1)
              .trim()
              .toUpperCase();
          widget.controller.text = newName;
          widget.onVendorSelected?.call(newName);
        } else {
          final norm = selection.trim().toUpperCase();
          widget.controller.text = norm;
          widget.onVendorSelected?.call(norm);
        }
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.business_rounded, size: 20),
            suffixIcon: textEditingController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      textEditingController.clear();
                      widget.onVendorSelected?.call('');
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            widget.onVendorSelected?.call(val);
          },
          onFieldSubmitted: (val) {
            onFieldSubmitted();
            widget.onVendorSelected?.call(val);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  final isNewOption = option.startsWith("+ Add new vendor '");

                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    title: Text(
                      option,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isNewOption ? FontWeight.bold : FontWeight.w500,
                        color: isNewOption
                            ? primaryRed
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
                    ),
                    leading: Icon(
                      isNewOption
                          ? Icons.add_circle_outline_rounded
                          : Icons.business_rounded,
                      size: 18,
                      color: isNewOption
                          ? primaryRed
                          : (isDark
                              ? const Color(0xFF94A3B8)
                              : Colors.grey.shade600),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
