import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:only_head/main.dart';

void main() {
  testWidgets('홈 화면 기본 렌더링', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OnlyHeadApp()));

    expect(find.text('Only Head'), findsOneWidget);
    expect(find.text('갤러리에서 선택'), findsOneWidget);
    expect(find.text('카메라로 촬영'), findsOneWidget);
  });
}
