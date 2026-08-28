import 'package:flutter/material.dart';

/// Reusable Real-time Vendor Search & Autocomplete Dropdown component.
/// Displays existing vendor matches or an option to create a new vendor when no exact match exists.
class VendorSearchAutocomplete extends StatelessWidget {
  final TextEditingController controller;
  final List<String> existingVendors;
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
  Widget build(BuildContext context) {
    const Color primaryRed = Color(0xFFD71920);

    // Filter non-empty vendors & sort alphabetically
    final List<String> vendorsList = existingVendors
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: FocusNode(),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim();
        if (query.isEmpty) {
          return vendorsList;
        }

        final matches = vendorsList
            .where((v) => v.toLowerCase().contains(query.toLowerCase()))
            .toList();

        final hasExactMatch = vendorsList.any(
          (v) => v.toLowerCase() == query.toLowerCase(),
        );

        if (!hasExactMatch) {
          matches.add("+ Add new vendor '$query'");
        }

        return matches;
      },
      onSelected: (String selection) {
        if (selection.startsWith("+ Add new vendor '") &&
            selection.endsWith("'")) {
          final newName = selection
              .substring("+ Add new vendor '".length, selection.length - 1)
              .trim();
          controller.text = newName;
          onVendorSelected?.call(newName);
        } else {
          controller.text = selection;
          onVendorSelected?.call(selection);
        }
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          validator: validator,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.business_rounded, size: 20),
            suffixIcon: textEditingController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      textEditingController.clear();
                      onVendorSelected?.call('');
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            onVendorSelected?.call(val);
          },
          onFieldSubmitted: (val) {
            onFieldSubmitted();
            onVendorSelected?.call(val);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: 280,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
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
                        color: isNewOption ? primaryRed : Colors.black87,
                      ),
                    ),
                    leading: Icon(
                      isNewOption
                          ? Icons.add_circle_outline_rounded
                          : Icons.business_rounded,
                      size: 18,
                      color: isNewOption ? primaryRed : Colors.grey.shade600,
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
