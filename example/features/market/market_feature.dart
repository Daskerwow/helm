export 'market_state.dart';

import 'package:helm/helm.dart';
import 'package:helm/flutter.dart';

import '../../data/market/market_socket.dart';
import 'market_state.dart';

final class WatchMarketCommand implements IStreamCommand<MarketState> {
  const WatchMarketCommand(this._socket);

  final MarketSocket _socket;

  @override
  Stream<void> execute(
    IStateReader<MarketState> reader,
    IStateWriter<MarketState> writer,
  ) {
    writer.commit(reader.current.copyWith(status: ConnectionStatus.connecting));

    return _socket.events().map((event) {
      switch (event) {
        case MarketSocketConnected():
          writer.commit(reader.current.copyWith(status: ConnectionStatus.live));

        case MarketSocketReconnecting():
          writer.commit(
            reader.current.copyWith(status: ConnectionStatus.reconnecting),
          );

        case MarketTickerUpdated(:final ticker):
          final next = Map<String, Ticker>.of(reader.current.tickers)
            ..[ticker.symbol] = ticker;
          writer.commit(
            MarketState(status: ConnectionStatus.live, tickers: next),
          );
      }
    });
  }
}

HelmFeature<MarketState, Never> buildMarketFeature(MarketSocket socket) {
  final feature = HelmFeature<MarketState, Never>(
    () => StoreBuilder<MarketState, Never>(
      const MarketState(),
    ).disableStreamDispatchLogging().build(),
  );

  feature.dispatchStream(WatchMarketCommand(socket));
  return feature;
}
