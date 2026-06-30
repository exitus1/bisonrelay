import 'dart:async';
import 'dart:collection';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chat/new_gc_screen.dart';
import 'package:bruig/screens/chat/new_message_screen.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/contacts_msg_times.dart';
import 'package:bruig/screens/gc_invitations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/user_context_menu.dart';
import 'package:bruig/components/gc_context_menu.dart';
import 'package:bruig/components/chat/types.dart';
import 'package:bruig/theme_manager.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:file_picker/file_picker.dart';

class _ChatHeadingW extends StatefulWidget {
  final ChatModel chat;
  final ClientModel client;
  final MakeActiveCB makeActive;
  final ShowSubMenuCB showSubMenu;
  final bool isActiveRTC;

  const _ChatHeadingW(
    this.chat,
    this.client,
    this.makeActive,
    this.showSubMenu,
    this.isActiveRTC,
  );

  @override
  State<_ChatHeadingW> createState() => _ChatHeadingWState();
}

class _ChatHeadingWState extends State<_ChatHeadingW> {
  ChatModel get chat => widget.chat;
  ClientModel get client => widget.client;
  bool get isActiveRTC => widget.isActiveRTC;

  void chatUpdated() => setState(() {});

  @override
  void initState() {
    chat.addListener(chatUpdated);
    super.initState();
  }

  @override
  void didUpdateWidget(_ChatHeadingW oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.chat.removeListener(chatUpdated);
    chat.addListener(chatUpdated);
  }

  @override
  void dispose() {
    chat.removeListener(chatUpdated);
    super.dispose();
  }

  // Cheap last-message preview: first loaded message event's text.
  // Blank for chats whose history isn't loaded this session (zero risk).
  // Prefix "You: " for your own messages; in group chats, prefix the
  // sender's nick so you can tell who said what. (source == null => local user.)
  // Replace --embed[...]-- markers with a clean label based on their type,
  // so previews show "Audio note" / "Image" instead of raw embed markup.
  String _cleanEmbeds(String src) {
    return src.replaceAllMapped(RegExp(r'--embed\[(.*?)\]--'), (m) {
      final attrs = m.group(1) ?? '';
      final type = RegExp(r'type=([^,\]]+)').firstMatch(attrs)?.group(1) ?? '';
      if (type.startsWith('image/')) return 'Image';
      if (type.startsWith('audio/')) return 'Audio note';
      if (type.startsWith('video/')) return 'Video';
      return 'File';
    });
  }

  String? _lastMsgPreview() {
    // Unsent draft takes priority in the preview.
    final draft = chat.workingMsg.trim();
    if (draft.isNotEmpty) return "Draft: ${draft.replaceAll('\n', ' ')}";
    for (final e in chat.msgs) {
      if (e.isMessage) {
        final t = _cleanEmbeds(e.event.msg).trim().replaceAll('\n', ' ');
        if (t.isEmpty) continue;
        if (e.source == null) return "You: $t";
        if (chat.isGC) {
          final who = e.source!.nick;
          if (who.isNotEmpty) return "$who: $t";
        }
        return t;
      }
    }
    return null;
  }

  // Relative time of the last loaded message: HH:MM if today, else 3d / 2w / date.
  // Mirrors BR's own seconds-vs-millis handling (source?.nick == null => local ms).
  String _lastMsgTime() {
    for (final e in chat.msgs) {
      if (!e.isMessage) continue;
      if (e.event.msg.trim().isEmpty) continue;
      final ev = e.event;
      int raw;
      if (ev is PM) {
        raw = ev.timestamp;
      } else if (ev is GCMsg) {
        raw = ev.timestamp;
      } else {
        continue;
      }
      final ms = e.source?.nick == null ? raw : raw * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final diff = DateTime.now().difference(dt);
      // Under 24h -> exact time the message was sent.
      if (diff.inHours < 24) {
        return "${dt.hour.toString().padLeft(2, '0')}:"
            "${dt.minute.toString().padLeft(2, '0')}";
      }
      final days = diff.inDays;
      if (days < 7) return "${days}d";
      if (days < 28) return "${(days / 7).floor()}w";
      return "${dt.month}/${dt.day}";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    // --- Redesign tokens ---
    const blue = Color(0xFF4D9FFF); // you / unread / search
    const green = Color(0xFF1DFF8C); // live / selected
    const nickColor = Color(0xFFE6EAE8);
    const previewMuted = Color(0xFF9AA3A0);
    const previewBright = Color(0xFFCED4D2);
    const selectedTint = Color(0x141DFF8C); // faint green wash

    final isActive = chat.active;
    final hasUnread = chat.unreadMsgCount > 0 || chat.unreadEventCount > 0;

    // Show 1k+ if unread count goes above 1000
    var unreadCount = chat.unreadMsgCount > 1000 ? "1k+" : chat.unreadMsgCount;

    Widget unreadIndicator;
    if (chat.unreadMsgCount > 0) {
      // Unread message count -> blue badge.
      unreadIndicator = Container(
        margin: const EdgeInsets.all(1),
        child: CircleAvatar(
          radius: 10,
          backgroundColor: blue,
          child: Text(
            "$unreadCount",
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF07101D),
            ),
          ),
        ),
      );
    } else if (chat.unreadEventCount > 0) {
      // Blue dot indicator.
      unreadIndicator = Container(
        margin: const EdgeInsets.all(1),
        child: const CircleAvatar(radius: 3, backgroundColor: blue),
      );
    } else {
      unreadIndicator = const SizedBox(width: 21);
    }

    var popMenuButton = InteractiveAvatar(
      chatNick: chat.nick,
      radius: 23,
      onTap: () {
        widget.makeActive(chat);
        widget.showSubMenu();
      },
      avatar: chat.avatar.image,
      toolTip: true,
    );

    // Nick (plain Text so we can use our blue when active).
    final nickWidget = Text(
      chat.nick,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        fontWeight: hasUnread
            ? FontWeight.w700
            : (isActive ? FontWeight.w600 : FontWeight.w500),
        color: isActive ? blue : nickColor,
      ),
    );

    // Last-message preview subtitle (null -> no subtitle).
    final preview = _lastMsgPreview();
    final Widget? subtitleWidget = preview == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.25,
                color: hasUnread ? previewBright : previewMuted,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          );

    // Last-message time + trailing column (time on top, unread badge below).
    final timeStr = _lastMsgTime();
    Widget trailingWith(Widget bottom) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timeStr.isNotEmpty) ...[
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: hasUnread ? blue : const Color(0xFF5F6764),
              ),
            ),
            const SizedBox(height: 6),
          ],
          bottom,
        ],
      );
    }

    // Rounded card. Inactive: plain rounded. Active: a green left edge that
    // FOLLOWS the rounded left corners (layered: green base + inner card inset
    // 3px on the left), plus a soft green glow.
    Widget wrapSelected(Widget tile) {
      const radius = 14.0;
      if (!isActive) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: tile,
          ),
        );
      }
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: blue.withValues(alpha: 0.15),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          // Reveal the green base as a curved left edge.
          padding: const EdgeInsets.only(left: 3),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(radius - 3),
              right: Radius.circular(radius),
            ),
            child: Container(
              color: const Color(0xFF0B0F16), // opaque dark-blue selected bg
              child: tile,
            ),
          ),
        ),
      );
    }

    bool isScreenSmall = checkIsScreenSmall(context);
    return Consumer<ThemeNotifier>(
      builder: (context, theme, _) => Container(
        child: chat.isGC
            ? GcContexMenu(
                mobile: isScreenSmall
                    ? (context) {
                        widget.makeActive(chat);
                        widget.showSubMenu();
                      }
                    : null,
                targetGcChat: chat,
                child: wrapSelected(ListTile(
                  horizontalTitleGap: 12,
                  contentPadding: const EdgeInsets.only(
                    left: 10,
                    right: 8,
                  ),
                  minVerticalPadding: 20,
                  enabled: true,
                  title: nickWidget,
                  subtitle: subtitleWidget,
                  leading: popMenuButton,
                  trailing: trailingWith(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "gc",
                        style: theme.extraTextStyles.chatListGcIndicator,
                      ),
                      const SizedBox(width: 5),
                      unreadIndicator,
                    ],
                  )),
                  selected: isActive,
                  selectedTileColor: Colors.transparent,
                  onTap: () => widget.makeActive(chat),
                )),
              )
            : UserContextMenu(
                client: client,
                targetUserChat: chat,
                child: wrapSelected(ListTile(
                  tileColor: isActiveRTC ? Colors.green.shade600 : null,
                  selectedTileColor:
                      isActiveRTC ? Colors.green.shade600 : Colors.transparent,
                  horizontalTitleGap: 12,
                  contentPadding: const EdgeInsets.only(
                    left: 10,
                    right: 8,
                  ),
                  minVerticalPadding: 20,
                  enabled: true,
                  title: nickWidget,
                  subtitle: subtitleWidget,
                  leading: popMenuButton,
                  trailing: trailingWith(unreadIndicator),
                  selected: isActive,
                  onTap: () => widget.makeActive(chat),
                )),
              ),
      ),
    );
  }
}

Future<void> generateInvite(BuildContext context) async {
  Navigator.of(context, rootNavigator: true).pushNamed('/generateInvite');
}

Future<void> fetchInvite(BuildContext context) async {
  Navigator.of(context, rootNavigator: true).pushNamed('/fetchInvite');
}

void gotoContactsLastMsgTimeScreen(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).pushNamed(ContactsLastMsgTimesScreen.routeName);
}

class ActiveChatsListMenu extends StatefulWidget {
  final ClientModel client;
  final CustomInputFocusNode inputFocusNode;
  final RealtimeChatModel rtc;
  const ActiveChatsListMenu(this.client, this.inputFocusNode, this.rtc,
      {super.key});

  @override
  State<ActiveChatsListMenu> createState() => _ActiveChatsListMenuState();
}

Future<void> loadInvite(BuildContext context) async {
  // Decode the invite and send to the user verification screen.
  var filePickRes = await FilePicker.platform.pickFiles();
  if (filePickRes == null) return;
  var filePath = filePickRes.files.first.path;
  if (filePath == null) return;
  filePath = filePath.trim();
  if (filePath == "") return;
  var invite = await Golib.decodeInvite(filePath);
  if (context.mounted) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed('/verifyInvite', arguments: invite);
  }
}

class _FooterIconButton extends StatelessWidget {
  final bool onlyWhenOnline;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final String? tag;
  const _FooterIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onlyWhenOnline = false,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeNotifier, ConnStateModel>(
      builder: (context, theme, connState, child) => Stack(
        children: [
          IconButton(
            splashRadius: 15,
            iconSize: 15,
            tooltip: !onlyWhenOnline || connState.isOnline
                ? tooltip
                : "Cannot perform this action when offline",
            disabledColor: theme.theme.disabledColor,
            onPressed: !onlyWhenOnline || connState.isOnline ? onPressed : null,
            icon: Icon(icon, size: 20),
          ),
          if ((tag ?? "") != "")
            Positioned(
              right: 0,
              child: Box(
                borderRadius: BorderRadius.circular(5),
                padding: EdgeInsets.all(2),
                color: SurfaceColor.primary,
                child: Txt.S(tag!),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallScreenFabIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _SmallScreenFabIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeNotifier, ConnStateModel>(
      builder: (context, theme, connState, child) => Material(
        borderRadius: BorderRadius.circular(30),
        color: theme.colors.surfaceContainerHigh.withValues(alpha: 0.7),
        child: Stack(
          children: [
            IconButton(
              splashRadius: 28,
              hoverColor: theme.colors.surfaceContainerHigh,
              iconSize: 40,
              tooltip: tooltip,
              disabledColor: theme.theme.disabledColor,
              onPressed: onPressed,
              icon: Icon(icon, size: 49),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChatsListMenuState extends State<ActiveChatsListMenu>
    with SingleTickerProviderStateMixin {
  ClientModel get client => widget.client;
  FocusNode get inputFocusNode => widget.inputFocusNode.inputFocusNode;
  RealtimeChatModel get rtc => widget.rtc;
  UnmodifiableListView<ChatModel> chats = UnmodifiableListView([]);
  Timer? debounce;
  ScrollController sortedListScroll = ScrollController();

  // Width of the resizable contact list pane (drag the divider to resize).
  double _listWidth = 320;

  void doUpdateState() {
    if (mounted) {
      setState(() {
        chats = client.activeChats.sorted;
      });
    }
    debounce = null;
  }

  void activeChatsListUpdated() {
    // Limit changes when updating chat list very fast.
    debounce ??= Timer(const Duration(milliseconds: 250), doUpdateState);
  }

  void genInvite() async {
    await generateInvite(context);
    inputFocusNode.requestFocus();
  }

  void showGCInvitationsScreen() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed(GCInvitationsScreen.routeName);
  }

  // Returns a callback to make chat c active.
  void makeActive(ChatModel? c) => {client.active = c};

  void showSubMenu() => client.ui.chatSideMenuActive.chat = client.active;

  void gotoNewMessage() =>
      Navigator.of(context).pushNamed(NewMessageScreen.routeName);

  void gotoNewGroupChat() =>
      Navigator.of(context).pushNamed(NewGcScreen.routeName);

  bool hasLiveRTCSess = false;
  bool hasHotAudio = false;
  bool get hasAnimation => hasLiveRTCSess || hasHotAudio;

  late AnimationController bgColorCtrl;
  late Animation<Color?> bgColorAnim;

  void rtcChanged() {
    bool newHasHotAudio = rtc.hotAudioSession.active?.inLiveSession ?? false;
    bool newHasLive = rtc.liveSessions.hasSessions;
    if (newHasLive != hasLiveRTCSess || newHasHotAudio != hasHotAudio) {
      setState(() {
        hasLiveRTCSess = newHasLive;
        hasHotAudio = newHasHotAudio;
      });
      if (hasAnimation) {
        bgColorCtrl.repeat();
      } else {
        bgColorCtrl.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    client.activeChats.addListener(activeChatsListUpdated);
    activeChatsListUpdated();

    rtc.hotAudioSession.addListener(rtcChanged);
    rtc.liveSessions.addListener(rtcChanged);

    // Initialize animation controller
    bgColorCtrl = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Create the color animation sequence
    bgColorAnim = TweenSequence<Color?>([
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade600,
          end: Colors.green.shade900,
        ),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade900,
          end: Colors.green.shade600,
        ),
      ),
    ]).animate(bgColorCtrl);
  }

  @override
  void didUpdateWidget(ActiveChatsListMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != client) {
      oldWidget.client.activeChats.removeListener(activeChatsListUpdated);
      client.activeChats.addListener(activeChatsListUpdated);
      activeChatsListUpdated();
    }
  }

  @override
  void dispose() {
    client.activeChats.removeListener(activeChatsListUpdated);

    bgColorCtrl.dispose();
    rtc.hotAudioSession.removeListener(rtcChanged);
    rtc.liveSessions.removeListener(rtcChanged);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);

    // Mobile version, display list of chats in entire screen.
    if (isScreenSmall) {
      return Container(
        padding: const EdgeInsets.all(0),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.only(
                left: 0,
                right: 5,
                top: 5,
                bottom: 5,
              ),
              child: ListView.builder(
                physics: const ScrollPhysics(),
                controller: sortedListScroll,
                scrollDirection: Axis.vertical,
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (context, index) => _ChatHeadingW(
                    chats[index],
                    client,
                    makeActive,
                    showSubMenu,
                    chats[index].hasInstantCall),
              ),
            ),
            Positioned(
              bottom: 20,
              right: 10,
              child: _SmallScreenFabIconButton(
                tooltip: "New Message",
                icon: Icons.edit_outlined,
                onPressed: gotoNewMessage,
              ),
            ),
            Positioned(
              bottom: 100,
              right: 10,
              child: _SmallScreenFabIconButton(
                tooltip: "Create new group chat",
                icon: Icons.people_outlined,
                onPressed: gotoNewGroupChat,
              ),
            ),
          ],
        ),
      );
    }

    // Desktop version, display side menu.
    return Consumer<ThemeNotifier>(
      builder: (context, theme, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _listWidth + 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Always-visible search bar -> opens user/GC search.
                  GestureDetector(
                    onTap: gotoNewMessage,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0E0D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1C1F1D)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.search,
                            size: 18, color: Color(0xFF5F6764)),
                        SizedBox(width: 10),
                        Text("Search or start a chat",
                            style: TextStyle(
                                fontSize: 13.5, color: Color(0xFF5F6764))),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: SecondarySideMenuList(
                      width: _listWidth,
                      list: ListView.builder(
          controller: sortedListScroll,
          scrollDirection: Axis.vertical,
          itemCount: chats.length,
          itemBuilder: (context, index) => SecondarySideMenuItem(
            _ChatHeadingW(chats[index], client, makeActive, showSubMenu,
                chats[index].hasInstantCall),
          ),
        ),
        footer: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.start,
            children: [
              _FooterIconButton(
                onlyWhenOnline: true,
                tooltip: "Generate Invite",
                onPressed: genInvite,
                icon: Icons.add_outlined,
              ),
              _FooterIconButton(
                tooltip: "List last received message time",
                onPressed: () => gotoContactsLastMsgTimeScreen(context),
                icon: Icons.list_outlined,
              ),
              _FooterIconButton(
                onlyWhenOnline: true,
                tooltip: "Fetch, import or accept invite",
                onPressed: () => fetchInvite(context),
                icon: Icons.get_app_outlined,
              ),
              _FooterIconButton(
                tooltip: "Create new group chat",
                onPressed: gotoNewGroupChat,
                icon: Icons.people_outline,
              ),
              _FooterIconButton(
                tooltip: "New Message",
                onPressed: gotoNewMessage,
                icon: Icons.edit_outlined,
              ),
              Consumer<GCInviteCountModel>(
                  builder: (context, gcInviteCount, child) => _FooterIconButton(
                        tooltip: "Show GC Invitations",
                        onPressed: showGCInvitationsScreen,
                        icon: Icons.groups,
                        tag: gcInviteCount.value == 0
                            ? null
                            : gcInviteCount.value > 9
                                ? "9+"
                                : gcInviteCount.value.toString(),
                      )),
            ],
          ),
        ),
                    ),
                  ),
                ],
              ),
            ),
            // Drag divider: drag to resize, double-tap to reset width.
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _listWidth =
                        (_listWidth + d.delta.dx).clamp(220.0, 560.0).toDouble();
                  });
                },
                onDoubleTap: () => setState(() => _listWidth = 320),
                child: const SizedBox(
                  width: 8,
                  child: Center(
                    child: SizedBox(
                      width: 1,
                      child: ColoredBox(color: Color(0xFF2F3336)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
