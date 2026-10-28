enum SplitMode { equal, exact, percentage }

class FriendSplitInput {
  final String name;
  final String? upiVpa;
  final int exactPaise;
  final double percentage;

  const FriendSplitInput({
    required this.name,
    this.upiVpa,
    this.exactPaise = 0,
    this.percentage = 0,
  });
}

class ComputedSplitShare {
  final String name;
  final String? upiVpa;
  final int sharePaise;
  final bool isUser;

  const ComputedSplitShare({
    required this.name,
    this.upiVpa,
    required this.sharePaise,
    this.isUser = false,
  });
}

class SplitCalculator {
  /// Splits [totalPaise] across the user ("You") and [friends].
  /// Any rounding remainder paise is assigned to the user's share so the sum
  /// always equals [totalPaise] to the exact paisa.
  static List<ComputedSplitShare> calculate({
    required int totalPaise,
    required SplitMode mode,
    required List<FriendSplitInput> friends,
    double userPercentage = 0,
    int userExactPaise = 0,
  }) {
    if (friends.isEmpty || totalPaise <= 0) {
      return [
        ComputedSplitShare(name: 'You', sharePaise: totalPaise, isUser: true),
      ];
    }

    switch (mode) {
      case SplitMode.equal:
        final participantCount = friends.length + 1;
        final baseShare = totalPaise ~/ participantCount;
        final remainder = totalPaise - (baseShare * participantCount);

        return [
          ComputedSplitShare(
            name: 'You',
            sharePaise: baseShare + remainder,
            isUser: true,
          ),
          ...friends.map(
            (f) => ComputedSplitShare(
              name: f.name,
              upiVpa: f.upiVpa,
              sharePaise: baseShare,
            ),
          ),
        ];

      case SplitMode.exact:
        final friendSum = friends.fold<int>(
          0,
          (sum, f) => sum + f.exactPaise.clamp(0, totalPaise),
        );
        final userShare = userExactPaise > 0
            ? userExactPaise
            : (totalPaise - friendSum).clamp(0, totalPaise);
        return [
          ComputedSplitShare(name: 'You', sharePaise: userShare, isUser: true),
          ...friends.map(
            (f) => ComputedSplitShare(
              name: f.name,
              upiVpa: f.upiVpa,
              sharePaise: f.exactPaise.clamp(0, totalPaise),
            ),
          ),
        ];

      case SplitMode.percentage:
        var allocated = 0;
        final friendShares = <ComputedSplitShare>[];
        for (final f in friends) {
          final share = ((totalPaise * f.percentage) / 100.0).round().clamp(
                0,
                totalPaise,
              );
          allocated += share;
          friendShares.add(
            ComputedSplitShare(
              name: f.name,
              upiVpa: f.upiVpa,
              sharePaise: share,
            ),
          );
        }
        final userShare = (totalPaise - allocated).clamp(0, totalPaise);
        return [
          ComputedSplitShare(name: 'You', sharePaise: userShare, isUser: true),
          ...friendShares,
        ];
    }
  }

  static Uri buildUpiPaymentUri({
    required String payeeVpa,
    required String payeeName,
    required int amountPaise,
    required String note,
  }) {
    final rupees = (amountPaise / 100.0).toStringAsFixed(2);
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': payeeVpa.trim(),
        'pn': payeeName.trim(),
        'am': rupees,
        'cu': 'INR',
        'tn': note.trim(),
      },
    );
  }
}

