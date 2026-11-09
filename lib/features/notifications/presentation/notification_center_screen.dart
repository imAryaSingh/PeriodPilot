import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/presentation/local_auth_controller.dart';
import '../data/firebase_notification_service.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});
  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late final _profile = context.read<LocalAuthController>().profile!;
  late final _repository = context.read<FirebaseNotificationRepository>();
  late final _service = context.read<FirebaseNotificationService>();
  bool _isEnabling = false;
  AuthorizationStatus? _authorization;

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    try {
      final status = await _service.readAuthorizationStatus();
      if (!mounted) return;
      setState(() => _authorization = status);
      if ((status == AuthorizationStatus.authorized ||
              status == AuthorizationStatus.provisional) &&
          _service.webVapidKeyConfigured) {
        await _service.initialize(_profile);
      }
    } on Object {
      if (mounted) setState(() => _authorization = AuthorizationStatus.denied);
    }
  }

  Future<void> _enable() async {
    setState(() => _isEnabling = true);
    try {
      await _service.requestAndRegister();
      if (mounted) {
        setState(() => _authorization = AuthorizationStatus.authorized);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications are enabled on this device.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
      await _loadPermission();
    } finally {
      if (mounted) setState(() => _isEnabling = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: StreamBuilder<List<SchoolNotification>>(
      stream: _repository.watchForUser(_profile),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load notifications: ${snapshot.error}'),
          );
        }
        final notifications = snapshot.data ?? const <SchoolNotification>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _permissionCard(context),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notification history',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (notifications.isNotEmpty)
                  Text(
                    '${notifications.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting &&
                notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!snapshot.hasData &&
                snapshot.connectionState != ConnectionState.waiting)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No notifications yet. Assignment updates will appear here.',
                  ),
                ),
              ),
            if (notifications.isEmpty && snapshot.hasData)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No notifications yet. Assignment updates will appear here.',
                  ),
                ),
              ),
            for (final notification in notifications)
              _notificationCard(context, notification),
          ],
        );
      },
    ),
  );

  Widget _permissionCard(BuildContext context) {
    final configured = _service.webVapidKeyConfigured;
    final granted =
        _authorization == AuthorizationStatus.authorized ||
        _authorization == AuthorizationStatus.provisional;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: .96),
            colors.secondaryContainer.withValues(alpha: .92),
          ],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: colors.surface.withValues(alpha: .3),
            child: Icon(
              granted
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  granted
                      ? 'This device is registered'
                      : 'Get assignment alerts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  !configured
                      ? 'Web push needs the Firebase Web Push VAPID key at build time.'
                      : granted
                      ? 'Push alerts are enabled. You can also review past updates below.'
                      : 'Allow notifications to receive new substitute duty alerts on this device.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: .88),
                  ),
                ),
                if (!granted && configured) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _isEnabling ? null : _enable,
                    icon: _isEnabling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      _isEnabling ? 'Enabling…' : 'Enable notifications',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(BuildContext context, SchoolNotification item) {
    final theme = Theme.of(context);
    final timestamp = item.createdAt == null
        ? ''
        : '${item.createdAt!.day.toString().padLeft(2, '0')}/${item.createdAt!.month.toString().padLeft(2, '0')}/${item.createdAt!.year} · ${item.createdAt!.hour.toString().padLeft(2, '0')}:${item.createdAt!.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: item.isRead
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          child: Icon(
            item.isRead
                ? Icons.notifications_none_rounded
                : Icons.notifications_active_rounded,
            color: item.isRead
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          item.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.body),
              if (item.deliveryStatus == 'no_installations')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Push was not delivered. Enable alerts on a teacher device.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (item.deliveryStatus == 'pending' ||
                  item.deliveryStatus == 'sending')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Push delivery is pending.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              if (timestamp.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    timestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: item.isRead
            ? null
            : IconButton(
                tooltip: 'Mark as read',
                onPressed: () async {
                  try {
                    await _repository.markRead(_profile, item.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                },
                icon: const Icon(Icons.check_circle_outline_rounded),
              ),
        isThreeLine: timestamp.isNotEmpty,
      ),
    );
  }
}
