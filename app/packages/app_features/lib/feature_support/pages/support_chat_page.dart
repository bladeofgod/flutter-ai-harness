import 'dart:async';

import 'package:app_data/support.dart';
import 'package:app_media/app_media.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/support_media_picker.dart'
    show SupportMediaPickFailureCode, SupportMediaSource;
import '../controllers/support_chat_controller.dart';
import '../widgets/support_chat_components.dart';

final class SupportChatPage extends StatefulWidget {
  const SupportChatPage({
    required this.mediaResourceStore,
    required this.createController,
    required this.onOpenVoucher,
    required this.onOpenMedia,
    required this.onDone,
    super.key,
  });

  final MediaResourceStore mediaResourceStore;
  final SupportChatController Function() createController;
  final ValueChanged<Voucher> onOpenVoucher;
  final ValueChanged<SupportMediaContent> onOpenMedia;
  final VoidCallback onDone;

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

final class _SupportChatPageState extends State<SupportChatPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final SupportChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await _controller.send();
    if (sent && mounted) {
      _textController.clear();
      _focusNode.requestFocus();
    }
  }

  Future<void> _chooseMedia() async {
    if (_controller.isSendingMedia) {
      return;
    }
    _focusNode.unfocus();
    final source = await showModalBottomSheet<SupportMediaSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _SupportMediaSourceSheet(),
    );
    if (source == null || !mounted) {
      return;
    }
    final result = await _controller.sendMedia(source);
    if (!mounted || result is! SupportMediaSendFailed) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_mediaFailureMessage(result.code))));
  }

  @override
  Widget build(BuildContext context) => GetBuilder<SupportChatController>(
    init: _controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (controller) => Obx(() {
      final state = controller.viewState;
      final conversation = state is SupportChatData ? state.conversation : null;
      final canRate = conversation?.stage == SupportConversationStage.active;
      return _SupportMediaStoreScope(
        store: widget.mediaResourceStore,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Customer Support', style: supportHeading(size: 21)),
            actions: [
              if (canRate)
                IconButton(
                  key: const ValueKey('support-open-rating'),
                  tooltip: 'Rate service',
                  onPressed: controller.requestRatingFromUi,
                  icon: const Icon(Icons.star_outline),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: switch (state) {
              SupportChatLoading() => const Center(
                child: CircularProgressIndicator(
                  key: ValueKey('support-loading'),
                ),
              ),
              SupportChatError(:final failure) => _SupportError(
                failure: failure,
                onRetry: controller.retryFromUi,
              ),
              SupportChatData(:final conversation) =>
                switch (conversation.stage) {
                  SupportConversationStage.starting => _StartingQuestions(
                    questions: conversation.suggestedQuestions,
                    onSelect: controller.selectQuestionFromUi,
                  ),
                  SupportConversationStage.connecting ||
                  SupportConversationStage.typing ||
                  SupportConversationStage.active => _ConversationView(
                    conversation: conversation,
                    scrollRequest: controller.scrollRequest,
                    textController: _textController,
                    focusNode: _focusNode,
                    draft: controller.draft,
                    onDraftChanged: controller.updateDraft,
                    onSend: () => unawaited(_send()),
                    onAddMedia: () => unawaited(_chooseMedia()),
                    isSendingMedia: controller.isSendingMedia,
                    onOpenVoucher: widget.onOpenVoucher,
                    onOpenMedia: widget.onOpenMedia,
                  ),
                  SupportConversationStage.rating => _ServiceRating(
                    selectedRating: controller.selectedRating,
                    onSelect: controller.selectRating,
                    onSubmit: controller.submitRatingFromUi,
                  ),
                  SupportConversationStage.rated => _RatingComplete(
                    rating: conversation.rating!,
                    onDone: widget.onDone,
                  ),
                },
            },
          ),
        ),
      );
    }),
  );
}

final class _SupportMediaStoreScope extends InheritedWidget {
  const _SupportMediaStoreScope({required this.store, required super.child});

  final MediaResourceStore store;

  static MediaResourceStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SupportMediaStoreScope>();
    assert(scope != null, 'Support media store scope is missing.');
    return scope!.store;
  }

  @override
  bool updateShouldNotify(_SupportMediaStoreScope oldWidget) =>
      !identical(store, oldWidget.store);
}

final class _SupportError extends StatelessWidget {
  const _SupportError({required this.failure, required this.onRetry});

  final SupportFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.support_agent, size: 52, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Support chat is unavailable',
            textAlign: TextAlign.center,
            style: supportHeading(size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            failure.code == SupportFailureCode.invalidState
                ? 'Restart the local Demo conversation.'
                : 'Try loading the local conversation again.',
            textAlign: TextAlign.center,
            style: supportBody(color: const Color(0xFF707070)),
          ),
          const SizedBox(height: 20),
          SupportPrimaryButton(
            key: const ValueKey('support-retry'),
            label: 'Retry',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    ),
  );
}

final class _StartingQuestions extends StatelessWidget {
  const _StartingQuestions({required this.questions, required this.onSelect});

  final List<SuggestedQuestion> questions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: const ValueKey('support-starting'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.maxHeight - 56,
          maxWidth: 520,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: AppColors.primarySurface,
              child: Icon(
                Icons.support_agent,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How can we help?',
              textAlign: TextAlign.center,
              style: supportHeading(size: 27),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a topic to start a local Demo conversation.',
              textAlign: TextAlign.center,
              style: supportBody(
                size: 15,
                height: 1.45,
                color: const Color(0xFF707070),
              ),
            ),
            const SizedBox(height: 28),
            for (final question in questions) ...[
              OutlinedButton.icon(
                key: ValueKey('support-question-${question.id}'),
                onPressed: () => onSelect(question.id),
                icon: const Icon(Icons.chat_bubble_outline, size: 19),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    question.label,
                    textAlign: TextAlign.left,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFE0E4EC)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: supportBody(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

final class _ConversationView extends StatelessWidget {
  const _ConversationView({
    required this.conversation,
    required this.scrollRequest,
    required this.textController,
    required this.focusNode,
    required this.draft,
    required this.onDraftChanged,
    required this.onSend,
    required this.onAddMedia,
    required this.isSendingMedia,
    required this.onOpenVoucher,
    required this.onOpenMedia,
  });

  final SupportConversation conversation;
  final int scrollRequest;
  final TextEditingController textController;
  final FocusNode focusNode;
  final String draft;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSend;
  final VoidCallback onAddMedia;
  final bool isSendingMedia;
  final ValueChanged<Voucher> onOpenVoucher;
  final ValueChanged<SupportMediaContent> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final isActive = conversation.stage == SupportConversationStage.active;
    return Column(
      children: [
        _ConnectionStatus(stage: conversation.stage),
        Expanded(
          child: _MessageList(
            messages: conversation.messages,
            scrollRequest: scrollRequest,
            onOpenVoucher: onOpenVoucher,
            onOpenMedia: onOpenMedia,
          ),
        ),
        _MessageComposer(
          textController: textController,
          focusNode: focusNode,
          enabled: isActive,
          canSend: isActive && draft.trim().isNotEmpty,
          onChanged: onDraftChanged,
          onSend: onSend,
          onAddMedia: onAddMedia,
          isSendingMedia: isSendingMedia,
        ),
      ],
    );
  }
}

final class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.stage});

  final SupportConversationStage stage;

  @override
  Widget build(BuildContext context) {
    final (label, showProgress) = switch (stage) {
      SupportConversationStage.connecting => (
        'Connecting to local Demo support...',
        true,
      ),
      SupportConversationStage.typing => ('Alex is typing...', true),
      _ => ('Alex · Local Demo Support', false),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        key: ValueKey('support-status-${stage.name}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: AppColors.primarySurface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showProgress) ...[
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 9),
            ] else ...[
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 17,
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: supportBody(size: 13, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.scrollRequest,
    required this.onOpenVoucher,
    required this.onOpenMedia,
  });

  final List<SupportMessage> messages;
  final int scrollRequest;
  final ValueChanged<Voucher> onOpenVoucher;
  final ValueChanged<SupportMediaContent> onOpenMedia;

  @override
  State<_MessageList> createState() => _MessageListState();
}

final class _MessageListState extends State<_MessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _showBottomButton = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scheduleScroll(animated: false);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollRequest != widget.scrollRequest ||
        oldWidget.messages.length != widget.messages.length) {
      _scheduleScroll(animated: true);
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final shouldShow =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels >
        72;
    if (shouldShow != _showBottomButton && mounted) {
      setState(() => _showBottomButton = shouldShow);
    }
  }

  void _scheduleScroll({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (animated && !_reduceMotion(context)) {
        unawaited(_animateTo(target));
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _animateTo(double target) async {
    try {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } on Object catch (error, stackTrace) {
      if (mounted) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'app_features',
            context: ErrorDescription('while scrolling Support messages'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ListView.builder(
        key: const ValueKey('support-message-list'),
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) => _MessageBubble(
          message: widget.messages[index],
          onOpenVoucher: widget.onOpenVoucher,
          onOpenMedia: widget.onOpenMedia,
        ),
      ),
      if (_showBottomButton)
        Positioned(
          right: 16,
          bottom: 10,
          child: IconButton.filled(
            key: const ValueKey('support-scroll-bottom'),
            tooltip: 'Go to latest message',
            onPressed: () => _scheduleScroll(animated: true),
            icon: const Icon(Icons.arrow_downward),
          ),
        ),
    ],
  );
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onOpenVoucher,
    required this.onOpenMedia,
  });

  final SupportMessage message;
  final ValueChanged<Voucher> onOpenVoucher;
  final ValueChanged<SupportMediaContent> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final isCustomer = message.participant == SupportParticipant.customer;
    final content = switch (message.content) {
      SupportTextContent(:final text) => Text(
        text,
        style: supportBody(
          size: 15,
          height: 1.42,
          color: isCustomer ? Colors.white : AppColors.textPrimary,
        ),
      ),
      SupportVoucherContent(:final voucher, :final description) =>
        _VoucherMessage(
          voucher: voucher,
          description: description,
          onOpen: () => onOpenVoucher(voucher),
        ),
      SupportMediaContent() => _MediaMessage(
        content: message.content as SupportMediaContent,
        onOpen: () => onOpenMedia(message.content as SupportMediaContent),
      ),
    };
    return Semantics(
      label: isCustomer ? 'You' : 'Support',
      child: Align(
        alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: ValueKey('support-message-${message.id}'),
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(
            message.content is SupportVoucherContent ||
                    message.content is SupportMediaContent
                ? 6
                : 13,
          ),
          decoration: BoxDecoration(
            color: isCustomer ? AppColors.primary : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: content,
        ),
      ),
    );
  }
}

final class _MediaMessage extends StatelessWidget {
  const _MediaMessage({required this.content, required this.onOpen});

  final SupportMediaContent content;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final poster = _mediaPoster(content.poster);
    return Semantics(
      button: true,
      label: content.type == SupportMediaType.image
          ? 'Open image attachment'
          : 'Open video attachment',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 220,
          height: 160,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('support-open-media-preview'),
              onTap: onOpen,
              borderRadius: BorderRadius.circular(5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    MediaResourceThumbnail(
                      resourceId: content.resourceId,
                      store: _SupportMediaStoreScope.of(context),
                      width: 220,
                      height: 160,
                      poster: poster,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: const Color(0xAA000000),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  content.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: supportBody(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (content.duration case final duration?) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(duration),
                                  style: supportBody(
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

MediaPoster? _mediaPoster(SupportMediaPoster? poster) {
  if (poster == null) {
    return null;
  }
  try {
    return MediaPoster.png(
      bytes: poster.bytes,
      width: poster.width,
      height: poster.height,
    );
  } on ArgumentError {
    return null;
  }
}

final class _VoucherMessage extends StatelessWidget {
  const _VoucherMessage({
    required this.voucher,
    required this.description,
    required this.onOpen,
  });

  final Voucher voucher;
  final String description;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDDE3F1)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  voucher.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: supportHeading(size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${voucher.discount.format()} off · Code ${voucher.code}',
            style: supportBody(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: supportBody(
              size: 13,
              height: 1.4,
              color: const Color(0xFF707070),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: ValueKey('support-open-voucher-${voucher.id}'),
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('View vouchers'),
          ),
        ],
      ),
    ),
  );
}

final class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.textController,
    required this.focusNode,
    required this.enabled,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
    required this.onAddMedia,
    required this.isSendingMedia,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool enabled;
  final bool canSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAddMedia;
  final bool isSendingMedia;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('support-message-input'),
              controller: textController,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: enabled ? 'Message' : 'Please wait...',
                filled: true,
                fillColor: AppColors.surfaceMuted,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 48,
            child: IconButton(
              key: const ValueKey('support-add-media'),
              tooltip: 'Add photo or video',
              onPressed: enabled && !isSendingMedia ? onAddMedia : null,
              icon: isSendingMedia
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 48,
            child: Tooltip(
              message: 'Send message',
              child: FilledButton(
                key: const ValueKey('support-send-message'),
                onPressed: canSend ? onSend : null,
                child: const Text('Send'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _SupportMediaSourceSheet extends StatelessWidget {
  const _SupportMediaSourceSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      key: const ValueKey('support-media-source-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add media', style: supportHeading(size: 20)),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('support-media-source-camera'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo or video'),
            onTap: () => Navigator.of(context).pop(SupportMediaSource.camera),
          ),
          ListTile(
            key: const ValueKey('support-media-source-gallery'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            subtitle: const Text('Photo or video'),
            onTap: () => Navigator.of(context).pop(SupportMediaSource.gallery),
          ),
          TextButton(
            key: const ValueKey('support-media-source-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _mediaFailureMessage(SupportMediaPickFailureCode code) => switch (code) {
  SupportMediaPickFailureCode.permissionDenied =>
    'Camera or gallery access was not granted.',
  SupportMediaPickFailureCode.readFailed =>
    'The selected media could not be read.',
  SupportMediaPickFailureCode.tooLarge =>
    'Choose an image under 2 MB or a video under 50 MB.',
  SupportMediaPickFailureCode.invalidMedia => 'Choose a valid photo or video.',
  SupportMediaPickFailureCode.unavailable => 'The media picker is unavailable.',
};

final class _ServiceRating extends StatelessWidget {
  const _ServiceRating({
    required this.selectedRating,
    required this.onSelect,
    required this.onSubmit,
  });

  final int selectedRating;
  final ValueChanged<int> onSelect;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      key: const ValueKey('support-rating'),
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 46,
              backgroundColor: AppColors.primarySurface,
              child: Icon(
                Icons.favorite_outline,
                size: 42,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Rate our service',
              textAlign: TextAlign.center,
              style: supportHeading(size: 27),
            ),
            const SizedBox(height: 8),
            Text(
              'How was your local Demo support conversation?',
              textAlign: TextAlign.center,
              style: supportBody(
                size: 15,
                height: 1.45,
                color: const Color(0xFF707070),
              ),
            ),
            const SizedBox(height: 22),
            Semantics(
              label: selectedRating == 0
                  ? 'No rating selected'
                  : '$selectedRating of 5 stars selected',
              child: Row(
                children: List<Widget>.generate(5, (index) {
                  final score = index + 1;
                  return Expanded(
                    child: IconButton(
                      key: ValueKey('support-rating-$score'),
                      tooltip: '$score star${score == 1 ? '' : 's'}',
                      onPressed: () => onSelect(score),
                      icon: Icon(
                        score <= selectedRating
                            ? Icons.star
                            : Icons.star_border,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            SupportPrimaryButton(
              key: const ValueKey('support-submit-rating'),
              label: 'Submit rating',
              icon: Icons.check,
              onPressed: selectedRating == 0 ? null : onSubmit,
            ),
          ],
        ),
      ),
    ),
  );
}

final class _RatingComplete extends StatelessWidget {
  const _RatingComplete({required this.rating, required this.onDone});

  final ServiceRating rating;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      key: const ValueKey('support-rating-complete'),
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 46,
              backgroundColor: AppColors.primarySurface,
              child: Icon(Icons.check, size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Thank you',
              textAlign: TextAlign.center,
              style: supportHeading(size: 27),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ${rating.score}-star rating was saved for this Demo session.',
              textAlign: TextAlign.center,
              style: supportBody(
                size: 15,
                height: 1.45,
                color: const Color(0xFF707070),
              ),
            ),
            const SizedBox(height: 26),
            SupportPrimaryButton(
              key: const ValueKey('support-rating-done'),
              label: 'Done',
              icon: Icons.arrow_back,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    ),
  );
}

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
