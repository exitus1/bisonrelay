import 'dart:async';

import 'package:bruig/components/chat/instantcallscreen.dart';
import 'package:bruig/components/chat/chat_side_menu.dart';
import 'package:bruig/components/chat/record_audio.dart';
import 'package:bruig/components/chat/rtc_session_header.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/manage_gc.dart';
import 'package:bruig/components/typing_emoji_panel.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/components/profile.dart';
import 'package:bruig/components/chat/messages.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:bruig/components/chat/input.dart';
import 'package:golib_plugin/definitions.dart';

class ActiveChat extends StatefulWidget {
  final ClientModel client;
  final RealtimeChatModel rtc;
  final AudioModel audio;
  final CustomInputFocusNode inputFocusNode;
  const ActiveChat(this.client, this.rtc, this.audio, this.inputFocusNode,
      {super.key});

  @override
  State<ActiveChat> createState() => _ActiveChatState();
}

class _ActiveChatState extends State<ActiveChat> with RouteAware {
  ClientModel get client => widget.client;
  RealtimeChatModel get rtc => widget.rtc;
  UIStateModel get ui => widget.client.ui;
  CustomInputFocusNode get inputFocusNode => widget.inputFocusNode;
  ChatModel? chat;
  RTDTSessionModel? rtcSession;
  RTDTSessionModel? currentInstantSession;
  late ItemScrollController _itemScrollController;
  late ItemPositionsListener _itemPositionsListener;
  Timer? _debounce;

  // --- Per-chat local search state (opened from the chat header) ---
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  bool get _searchOpen => ui.chatSearch.val;

  // Reacts to the header Search button toggling ui.chatSearch.
  void _onSearchFlagChanged() {
    if (!mounted) return;
    if (!ui.chatSearch.val) {
      _searchQuery = "";
      _searchCtrl.clear();
    }
    setState(() {});
  }

  void _closeSearch() => ui.chatSearch.val = false;

  // Scroll the conversation to the message at the given index in chat.msgs.
  void _jumpToMsg(int index) {
    _closeSearch();
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        alignment: 0.35,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void activeChatChanged() {
    var newChat = client.active;
    if (newChat != chat) {
      // Reset search when switching chats.
      if (ui.chatSearch.val) ui.chatSearch.val = false;
      setState(() {
        chat = newChat;
        rtcSession = rtc.gcSession(newChat?.id ?? "");
        currentInstantSession = chat?.currentSessions(newChat?.id ?? "");
      });
    }
  }

  void _doSendMsg(String msg) async {
    var snackbar = SnackBarModel.of(context);
    try {
      await chat!.sendMsg(msg);
      client.newSentMsg(chat!);
    } catch (exception) {
      snackbar.error("Unable to send message: $exception");
    }
  }

  void sendMsg(String msg) {
    if (this.chat == null) {
      return;
    }
    ChatModel chat = this.chat!;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () async {
      if (!mounted) return;

      // The first time this client sends a message on a GC with unkxd members,
      // warn the user about it.
      var notifyGCUnkxdMembers = chat.isGC &&
          !(await StorageManager.readBool(
              StorageManager.notifiedGCUnkxdMembers)) &&
          (chat.unkxdMembers.value?.isNotEmpty ?? false);
      if (!mounted) return;
      if (notifyGCUnkxdMembers) {
        showModalBottomSheet(
            context: context,
            builder: (context) => Container(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      "Note: This GC contains un-kx'd members - other people whom this "
                      "client has not exchanged keys with. These people won't receive any "
                      "messages until the KX process has completed, which usually happens "
                      "automatically, once they come back online.\n\n"
                      "It is also common on large, public GCs to have people that never "
                      "come online because they have stopped using the software and have "
                      "not yet been removed from the GC.\n\n"
                      "You may wait until the warning indicator disappears or you "
                      "may keep sending messages (keeping in mind that not every "
                      "member of this GC will receive them).\n\n"
                      "This warning will be displayed only once."),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      StorageManager.saveBool(
                          StorageManager.notifiedGCUnkxdMembers, true);
                      Navigator.of(context).pop();
                      _doSendMsg(msg);
                    },
                    child: const Text("Ok"),
                  )
                ]))));
        return;
      }

      _doSendMsg(msg);
    });
  }

  void showProfileChanged() {
    setState(() {});
  }

  void chatSideMenuActiveChanged() {
    setState(() {});
  }

  void rtcSessionsChanged() {
    var newRtcSess = rtc.gcSession(chat?.id ?? "");
    if (newRtcSess != rtcSession) {
      setState(() {
        rtcSession = newRtcSess;
      });
    }
    var newInstantSession = chat?.currentSessions(chat?.id ?? "");
    if (newInstantSession != currentInstantSession) {
      setState(() {
        currentInstantSession = newInstantSession;
      });
    }
  }

  @override
  void didPopNext() {
    if (!checkIsScreenSmall(context)) {
      inputFocusNode.inputFocusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();
    chat = client.active;
    rtcSession = rtc.gcSession(chat?.id ?? "");
    currentInstantSession = chat?.currentSessions(chat?.id ?? "");
    client.activeChat.addListener(activeChatChanged);
    ui.showProfile.addListener(showProfileChanged);
    ui.chatSideMenuActive.addListener(chatSideMenuActiveChanged);
    ui.chatSearch.addListener(_onSearchFlagChanged);
    rtc.addListener(rtcSessionsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ui.overviewRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didUpdateWidget(ActiveChat oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(activeChatChanged);
      client.addListener(activeChatChanged);
      activeChatChanged();
      oldWidget.client.ui.showProfile.removeListener(showProfileChanged);
      ui.showProfile.addListener(showProfileChanged);
      oldWidget.client.ui.chatSideMenuActive
          .removeListener(chatSideMenuActiveChanged);
      ui.chatSideMenuActive.addListener(chatSideMenuActiveChanged);
    } else if (client.active != chat) {
      activeChatChanged();
    }

    // Fix this so it doesn't fire every update?
    var newInstantSession = chat?.currentSessions(chat?.id ?? "");
    setState(() {
      currentInstantSession = newInstantSession;
    });

    if (oldWidget.rtc != rtc) {
      oldWidget.rtc.removeListener(rtcSessionsChanged);
      rtc.addListener(rtcSessionsChanged);
    }
  }

  @override
  void dispose() {
    ui.showProfile.removeListener(showProfileChanged);
    ui.chatSideMenuActive.removeListener(chatSideMenuActiveChanged);
    ui.chatSearch.removeListener(_onSearchFlagChanged);
    ui.overviewRouteObserver.unsubscribe(this);
    _debounce?.cancel();
    _searchCtrl.dispose();
    client.activeChat.removeListener(activeChatChanged);
    rtc.removeListener(rtcSessionsChanged);
    super.dispose();
  }

  @override
  Widget _pinnedBar(ChatModel chat) {
    return AnimatedBuilder(
      animation: chat,
      builder: (context, _) {
        final msg = chat.pinnedMsg;
        if (msg == null || msg.isEmpty) return const SizedBox.shrink();
        var preview = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (preview.contains('--embed[')) preview = '[attachment]';
        final nick = chat.pinnedNick ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 5),
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            border: Border(
              left: BorderSide(color: Color(0xFF2C6BED), width: 3),
              bottom: BorderSide(color: Color(0xFF1C1C1C), width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.push_pin_outlined,
                color: Color(0xFF2C6BED), size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Pinned message",
                      style: TextStyle(
                          color: Color(0xFF5B8FE8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text.rich(
                    TextSpan(children: [
                      if (nick.isNotEmpty)
                        TextSpan(
                            text: "$nick: ",
                            style: const TextStyle(color: Color(0xFFA9C56C))),
                      TextSpan(text: preview),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0xFFCED4D2), fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 17,
              tooltip: "Unpin",
              onPressed: chat.clearPin,
              icon: const Icon(Icons.close, color: Color(0xFF6B6B6B)),
            ),
          ]),
        );
      },
    );
  }

  Widget build(BuildContext context) {
    if (this.chat == null) return Container();
    var chat = this.chat!;

    if (ui.showProfile.val) {
      if (chat.isGC) {
        return ManageGCScreen(client, rtc, chat);
      } else {
        return UserProfile(client);
      }
    }

    bool isScreenSmall = checkIsScreenSmall(context);

    if (currentInstantSession != null) {
      return InstantCallScreen(
          rtc, currentInstantSession!, widget.audio, client, chat);
    } else {
      return ScreenWithChatSideMenu(
          client,
          Column(
            children: [
              if (_searchOpen)
                _ChatSearchPanel(
                  chat: chat,
                  controller: _searchCtrl,
                  query: _searchQuery,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  onClose: _closeSearch,
                  onJump: _jumpToMsg,
                ),
              if (rtcSession != null)
                Box(
                  color: SurfaceColor.primaryContainer,
                  margin: const EdgeInsets.only(bottom: 5),
                  padding: const EdgeInsets.all(5),
                  child:
                      RTCSessionHeader(rtc, rtcSession!, widget.audio, client),
                ),
              _pinnedBar(chat),
              Expanded(
                child: Stack(children: [
                  Messages(chat, client, _itemScrollController,
                      _itemPositionsListener),
                  Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: Consumer<TypingEmojiSelModel>(
                          builder: (context, typingEmoji, child) =>
                              TypingEmojiPanel(
                                model: typingEmoji,
                                focusNode: inputFocusNode,
                              ))),
                  if (isScreenSmall)
                    Positioned(
                        left: 10,
                        bottom: 10,
                        right: 10,
                        child: Consumer<AudioModel>(
                            builder: (context, audio, child) =>
                                SmallScreenRecordInfoPanel(audio: audio))),
                ]),
              ),
              if (!chat.killed)
                Container(
                    padding: isScreenSmall
                        ? const EdgeInsets.all(10)
                        : const EdgeInsets.all(5),
                    child: ChatInput(sendMsg, chat, inputFocusNode))
            ],
          ));
    }
  }
}

// A single search match within the active chat.
class _SearchHit {
  final int index; // position in chat.msgs (maps directly to the scroll list)
  final String text;
  final String sender;
  final bool mine;
  final int tsMs;
  const _SearchHit({
    required this.index,
    required this.text,
    required this.sender,
    required this.mine,
    required this.tsMs,
  });
}

// Search bar + live results list, pinned to the top of the active chat.
// Searches only the locally-loaded messages of the selected chat.
class _ChatSearchPanel extends StatelessWidget {
  final ChatModel chat;
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final ValueChanged<int> onJump;

  const _ChatSearchPanel({
    required this.chat,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClose,
    required this.onJump,
  });

  static const _months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", //
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return "${_months[d.month - 1]} ${d.day}, $hh:$mm";
  }

  List<_SearchHit> _computeHits() {
    final q = query.trim().toLowerCase();
    final hits = <_SearchHit>[];
    if (q.isEmpty) return hits;
    final msgs = chat.msgs; // newest-first; index maps to the scroll list.
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (!m.isMessage) continue;
      final text = m.event.msg;
      if (text.toLowerCase().contains(q)) {
        final mine = m.source == null;
        final ev = m.event;
        int rawTs = 0;
        if (ev is PM) {
          rawTs = ev.timestamp;
        } else if (ev is GCMsg) {
          rawTs = ev.timestamp;
        }
        hits.add(_SearchHit(
          index: i,
          text: text,
          sender: m.source?.nick ?? "You",
          mine: mine,
          tsMs: mine ? rawTs : rawTs * 1000,
        ));
        if (hits.length >= 200) break; // cap for performance
      }
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hits = _computeHits();
    final hasQuery = query.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search bar row.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: onChanged,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  cursorColor: cs.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: "Search this conversation…",
                    hintStyle:
                        TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              if (hasQuery)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    hits.length >= 200 ? "200+" : "${hits.length}",
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: hits.isEmpty ? cs.onSurfaceVariant : cs.primary),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                splashRadius: 18,
                onPressed: onClose,
                tooltip: "Close search",
              ),
            ]),
          ),
          // Results list.
          if (hasQuery)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("No matches in this chat",
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 6),
                      itemCount: hits.length,
                      itemBuilder: (context, i) {
                        final h = hits[i];
                        return InkWell(
                          onTap: () => onJump(h.index),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(
                                    h.mine ? "You" : h.sender,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _fmtTime(h.tsMs),
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ]),
                                const SizedBox(height: 2),
                                Text(
                                  h.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.3,
                                      color: cs.onSurface),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
