/// Rewards Domain、本地数据源与 Fixture 的聚焦公共入口。
library;

export 'src/fixture/shoppe_voucher_fixture.dart' show shoppeFiveVoucherFixture;
export 'src/rewards/rewards_failure.dart';
export 'src/rewards/rewards_fixture_handler.dart' show RewardsFixtureHandler;
export 'src/rewards/rewards_local.dart'
    show RewardsLocalDataSource, RewardsMutationResult;
export 'src/rewards/rewards_models.dart';
