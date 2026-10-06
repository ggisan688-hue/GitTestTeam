import 'package:flutter/material.dart';

import '../../model/server_friend.dart';
import '../../repository/friend_repository.dart';

class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key, required this.repository});
  final FriendRepository repository;
  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen> {
  late Future<List<ServerFriend>> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.incomingServerRequests();
  }

  void reload() =>
      setState(() => future = widget.repository.incomingServerRequests());
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Friend requests')),
    body: FutureBuilder<List<ServerFriend>>(
      future: future,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty)
          return const Center(child: Text('No pending requests.'));
        return ListView(
          children: s.data!
              .map(
                (f) => ListTile(
                  title: Text(f.nickname),
                  subtitle: Text('@${f.username}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await widget.repository.respondServerRequest(
                            f.id,
                            false,
                          );
                          reload();
                        },
                        child: const Text('Decline'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          await widget.repository.respondServerRequest(
                            f.id,
                            true,
                          );
                          reload();
                        },
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
