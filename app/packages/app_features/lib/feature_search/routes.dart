import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/search_api.dart';
import '../api/search_image_picker.dart';
import 'api/shared_media_search_image_picker.dart';
import 'controllers/search_controller.dart';
import 'pages/search_page.dart';

const searchRoutePath = '/search';

typedef SearchProductNavigation =
    void Function(BuildContext context, String productId);

List<RouteBase> buildSearchRoutes({
  required SearchApi searchApi,
  required SearchProductNavigation openProduct,
  SearchImagePicker? imagePicker,
}) => <RouteBase>[
  GoRoute(
    path: searchRoutePath,
    builder: (context, state) => SearchPage(
      controller: SearchFlowController(
        searchApi: searchApi,
        imagePicker: imagePicker ?? SharedMediaSearchImagePicker(),
      ),
      onProductSelected: (productId) => openProduct(context, productId),
    ),
  ),
];
