import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CmsInvoiceScreen extends StatefulWidget {
  static const routeName = "/cms";
  const CmsInvoiceScreen({super.key});

  @override
  State<CmsInvoiceScreen> createState() => _CmsInvoiceScreenState();
}

class CmsInvoiceScreenTitle extends StatelessWidget {
  const CmsInvoiceScreenTitle({super.key});
  @override
  Widget build(BuildContext context) {
    return const Row(children: [Txt.L("CMS — Submit Invoice")]);
  }
}

// A single invoice line item with its own controllers.
class _LineItem {
  String type;
  final domain = TextEditingController();
  final subdomain = TextEditingController();
  final description = TextEditingController();
  final token = TextEditingController();
  final labor = TextEditingController(text: "0");
  final expenses = TextEditingController(text: "0");
  final rate = TextEditingController(text: "0");
  final subuid = TextEditingController(text: "0");
  _LineItem({this.type = "expense"});
  void dispose() {
    domain.dispose();
    subdomain.dispose();
    description.dispose();
    token.dispose();
    labor.dispose();
    expenses.dispose();
    rate.dispose();
    subuid.dispose();
  }
}

class _CmsInvoiceScreenState extends State<CmsInvoiceScreen> {
  // Palette (matches the BR redesign).
  static const _bg = Color(0xFF0A0A0A);
  static const _card = Color(0xFF0C0D0C);
  static const _fieldBg = Color(0xFF0E100E);
  static const _line = Color(0xFF1C1F1D);
  static const _line2 = Color(0xFF2F3336);
  static const _green = Color(0xFF1DFF8C);
  static const _blue = Color(0xFF4D9FFF);
  static const _text = Color(0xFFF2F4F3);
  static const _text2 = Color(0xFF9AA3A0);
  static const _text3 = Color(0xFF5F6764);

  String month = "1";
  String year = "2026";
  final name = TextEditingController();
  final location = TextEditingController();
  final rate = TextEditingController();
  final addr = TextEditingController();
  final List<_LineItem> items = [_LineItem()];

  @override
  void dispose() {
    for (final c in [name, location, rate, addr]) {
      c.dispose();
    }
    for (final it in items) {
      it.dispose();
    }
    super.dispose();
  }

  String _n(String s) => s.trim().isEmpty ? "0" : s.trim();

  String _buildTxt() {
    final b = StringBuffer();
    b.writeln("Month,$month");
    b.writeln("Year,$year");
    b.writeln("Name,${name.text.trim()}");
    b.writeln("Location,${location.text.trim()}");
    b.writeln("Rate,${rate.text.trim()}");
    b.writeln(
        "PaymentAddr,${addr.text.trim().isEmpty ? "(your address)" : addr.text.trim()}");
    b.writeln("# Below are where line items are specified");
    b.writeln("# The fields are in the order:");
    b.writeln(
        "#    type, domain, subdomain, description, proposalToken, labor, expenses, rate, subuid");
    b.writeln("#");
    b.writeln("# type must be one of these values: labor expense sub");
    for (final it in items) {
      final isLabor = it.type == "labor";
      b.writeln([
        it.type,
        it.domain.text.trim(),
        it.subdomain.text.trim(),
        it.description.text.trim(),
        it.token.text.trim(),
        isLabor ? _n(it.labor.text) : "0",
        isLabor ? "0" : _n(it.expenses.text),
        "0", // per-line rate unused
        "0", // subuid unused
      ].join(","));
    }
    return b.toString();
  }

  void _addItem() => setState(() => items.add(_LineItem()));

  void _removeItem(int i) => setState(() {
        items[i].dispose();
        items.removeAt(i);
      });

  void _copy() {
    Clipboard.setData(ClipboardData(text: _buildTxt()));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invoice copied to clipboard")));
  }

  Future<void> _save() async {
    try {
      final nm = name.text.trim().isEmpty
          ? "contractor"
          : name.text.trim().toLowerCase();
      final fileName = "invoice-$nm-$year-$month.txt";
      final path = await FilePicker.platform
          .saveFile(dialogTitle: "Save invoice", fileName: fileName);
      if (path == null) return;
      await File(path).writeAsString(_buildTxt());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Saved to $path")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Could not save: $e")));
      }
    }
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, bool enabled = true, double width = double.infinity}) {
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: _text2, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        TextField(
          controller: c,
          enabled: enabled,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13.5, color: _text),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: _text3),
            filled: true,
            fillColor: _fieldBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: _blue)),
            disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: _line)),
          ),
        ),
      ]),
    );
  }

  Widget _dropdown(String label, String value, List<String> options,
      void Function(String) onChanged,
      {double width = double.infinity}) {
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: _text2, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        Container(
          decoration: BoxDecoration(
            color: _fieldBg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: _card,
            style: const TextStyle(fontSize: 13.5, color: _text),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ]),
    );
  }

  Widget _sectionHeader(String s) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: _text3)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: _line),
        ]),
      );

  Widget _itemCard(int i) {
    final it = items[i];
    final isLabor = it.type == "labor";
    final isExpense = it.type == "expense";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF15171A),
                borderRadius: BorderRadius.circular(6)),
            child: Text("#${i + 1}",
                style: const TextStyle(fontSize: 11, color: _text2)),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<String>(
              value: it.type,
              underline: const SizedBox(),
              dropdownColor: _card,
              style: const TextStyle(fontSize: 13.5, color: _text),
              items: const [
                DropdownMenuItem(value: "labor", child: Text("labor")),
                DropdownMenuItem(value: "expense", child: Text("expense")),
              ],
              onChanged: (v) => setState(() => it.type = v ?? "expense"),
            ),
          ),
          const Spacer(),
          if (items.length > 1)
            TextButton.icon(
              onPressed: () => _removeItem(i),
              icon: const Icon(Icons.close, size: 15, color: _text3),
              label: const Text("remove",
                  style: TextStyle(fontSize: 13, color: _text3)),
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _field("Domain", it.domain, hint: "Marketing", width: 180),
          _field("Subdomain", it.subdomain, width: 180),
          _field("Proposal token", it.token, width: 220),
          _field("Description", it.description, width: 380),
          if (isLabor) _field("Labor (hours)", it.labor, width: 150),
          if (isExpense) _field("Expenses (amount)", it.expenses, width: 150),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txt = _buildTxt();
    return Container(
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        children: [
          const Text("Submit an invoice",
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w600, color: _text)),
          const SizedBox(height: 3),
          const Text(
              "Contractor Management System — fill in your details and line items, then copy or save the generated invoice.",
              style: TextStyle(fontSize: 13, color: _text3)),
          _sectionHeader("Invoice details"),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _dropdown(
                "Month",
                month,
                [for (var m = 1; m <= 12; m++) m.toString()],
                (v) => setState(() => month = v),
                width: 120),
            _dropdown(
                "Year",
                year,
                [for (var y = 2026; y <= 2030; y++) y.toString()],
                (v) => setState(() => year = v),
                width: 120),
            _field("Name", name, width: 240),
            _field("Location", location, width: 240),
            _field("Hourly Rate", rate, hint: "e.g. 25", width: 160),
            _field("Payment address", addr, hint: "Ds...", width: 320),
          ]),
          _sectionHeader("Line items"),
          ...List.generate(items.length, (i) => _itemCard(i)),
          OutlinedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add, size: 18, color: _green),
            label: const Text("Add line item",
                style: TextStyle(color: _green, fontWeight: FontWeight.w500)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _line2),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          _sectionHeader("Generated invoice.txt"),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: SelectableText(
              txt,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  letterSpacing: 0,
                  color: Color(0xFFCDD3D1)),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy, size: 17, color: _text),
                label: const Text("Copy", style: TextStyle(color: _text)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _line2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.download, size: 17, color: Color(0xFF04130B)),
                label: const Text("Save .txt",
                    style: TextStyle(
                        color: Color(0xFF04130B), fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
