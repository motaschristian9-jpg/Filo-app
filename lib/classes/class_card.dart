import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'class_editor.dart';

class ClassCard extends StatelessWidget {
  const ClassCard({super.key, required this.name, required this.subject,
    required this.section, required this.color, required this.onTap,
    this.footer = '', this.archived = false, this.instructor,
    this.details, this.footerContent, this.bannerSubtitle});
  final String? bannerSubtitle;
  final Widget? instructor, details, footerContent;
  final String name, subject, section, footer;
  final int color;
  final bool archived;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white, clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: line)),
    child: InkWell(onTap: onTap, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(constraints: const BoxConstraints(minHeight: 140),
          child: Ink(width: double.infinity,
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [classColor(color), Color.lerp(classColor(color), teal, .18)!])),
          child: Stack(children: [
            Positioned(right: -12, bottom: -16, child: ExcludeSemantics(
              child: Transform.rotate(angle: -.16, child: Icon(classIcon(color),
                size: 112, color: teal.withValues(alpha: .12))))),
            Padding(padding: const EdgeInsets.all(20), child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, height: 1.2,
                    color: ink, fontWeight: FontWeight.w900)),
                if (bannerSubtitle != null && bannerSubtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(bannerSubtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontWeight: FontWeight.w600)),
                ],
                if (section.trim().isNotEmpty &&
                    section.trim().toLowerCase() != name.trim().toLowerCase()) ...[
                  const SizedBox(height: 8),
                  Text(section, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontWeight: FontWeight.w600)),
                ],
                if (instructor != null) ...[
                  const SizedBox(height: 12),
                  instructor!,
                ],
              ])),
          ]))),
        if (details != null) Padding(padding: const EdgeInsets.all(20), child: details!)
        else Padding(padding: const EdgeInsets.all(20), child: Row(children: [
          Icon(Icons.auto_stories_outlined, color: teal, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(subject.isEmpty ? name : subject,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ink, fontWeight: FontWeight.w700))),
        ])),
        const Divider(height: 1, color: line),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            if (footerContent == null && archived) ...[
              const Icon(Icons.inventory_2_outlined, size: 16, color: teal),
              const SizedBox(width: 8),
            ],
            if (footerContent != null) Expanded(child: footerContent!)
            else Expanded(child: Text(archived ? 'Archived' : footer,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall)),
            const Icon(Icons.arrow_forward_rounded, color: teal, size: 20),
          ])),
      ])),
  );
}
