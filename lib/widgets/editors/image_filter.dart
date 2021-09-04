import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:advance_image_picker/configs/image_picker_configs.dart';
import 'package:advance_image_picker/utils/image_utils.dart';
import 'package:advance_image_picker/utils/time_utils.dart';
import 'package:advance_image_picker/widgets/common/portrait_mode_mixin.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart' as PathProvider;

/// Image filter widget
class ImageFilter extends StatefulWidget {
  ImageFilter(
      {Key? key,
      required this.title,
      required this.file,
      this.configs,
      this.maxWidth = 1280,
      this.maxHeight = 720})
      : super(key: key);

  /// Input file object
  final File file;

  /// Title for image edit widget
  final String title;

  /// Max width
  final int maxWidth;

  /// Max height
  final int maxHeight;

  /// Configuration
  final ImagePickerConfigs? configs;

  @override
  State<StatefulWidget> createState() => new _ImageFilterState();
}

class _ImageFilterState extends State<ImageFilter>
    with PortraitStatefulModeMixin<ImageFilter> {
  Map<String, List<int>?> _cachedFilters = {};
  ListQueue<MapEntry<String, Future<List<int>?> Function()>>
      _queuedApplyFilterFuncList =
      ListQueue<MapEntry<String, Future<List<int>?> Function()>>();
  int _runningCount = 0;
  late Filter _filter;
  late List<Filter> _filters;
  Uint8List? _imageBytes;
  Uint8List? _thumbnailImageBytes;
  late bool _loading;
  ImagePickerConfigs _configs = ImagePickerConfigs();

  @override
  void initState() {
    super.initState();
    if (widget.configs != null) _configs = widget.configs!;

    _loading = true;
    _filters = _getPresetFilters();
    _filter = this._filters[0];

    Future.delayed(const Duration(milliseconds: 500), () async {
      await _loadImageData();
    });
  }

  @override
  void dispose() {
    _filters.clear();
    _cachedFilters.clear();
    _queuedApplyFilterFuncList.clear();
    super.dispose();
  }

  Future<void> _loadImageData() async {
    _imageBytes = await widget.file.readAsBytes();
    _thumbnailImageBytes = await (await ImageUtils.compressResizeImage(
            widget.file.path,
            maxWidth: 100,
            maxHeight: 100))
        .readAsBytes();

    setState(() {
      _loading = false;
    });
  }

  Future<List<int>?> _getFilteredData(String key) async {
    if (_cachedFilters.containsKey(key))
      return _cachedFilters[key];
    else {
      return await Future.delayed(
          const Duration(milliseconds: 500), () => _getFilteredData(key));
    }
  }

  void _runApplyFilterProcess() async {
    while (_queuedApplyFilterFuncList.isNotEmpty) {
      if (!this.mounted) break;

      if (_runningCount > 2) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      print("_runningCount: " + _runningCount.toString());

      var func = _queuedApplyFilterFuncList.removeFirst();
      _runningCount++;
      var ret = await func.value.call();
      _cachedFilters[func.key] = ret;
      _runningCount--;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Use theme based AppBar colors if config values are not defined.
    // The logic is based on same approach that is used in AppBar SDK source.
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppBarTheme appBarTheme = AppBarTheme.of(context);
    // TODO: Track AppBar theme backwards compatibility in Flutter SDK.
    // The AppBar theme backwards compatibility will be deprecated in Flutter
    // SDK soon. When that happens it will be removed here too.
    final bool backwardsCompatibility =
        appBarTheme.backwardsCompatibility ?? false;
    final Color _appBarBackgroundColor = backwardsCompatibility
        ? _configs.appBarBackgroundColor ??
            appBarTheme.backgroundColor ??
            theme.primaryColor
        : _configs.appBarBackgroundColor ??
            appBarTheme.backgroundColor ??
            (colorScheme.brightness == Brightness.dark
                ? colorScheme.surface
                : colorScheme.primary);
    final Color _appBarTextColor = _configs.appBarTextColor ??
        appBarTheme.foregroundColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.onSurface
            : colorScheme.onPrimary);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: _appBarBackgroundColor,
        foregroundColor: _appBarTextColor,
        actions: <Widget>[
          _loading
              ? Container()
              : IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () async {
                    setState(() {
                      _loading = true;
                    });
                    var imageFile = await saveFilteredImage();
                    Navigator.pop(context, imageFile);
                  },
                )
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        child: _loading
            ? const CupertinoActivityIndicator()
            : Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      child: _buildFilteredWidget(_filter, _imageBytes!),
                    ),
                  ),
                  Container(
                    height: 150,
                    padding: const EdgeInsets.all(12.0),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      itemBuilder: (BuildContext context, int index) {
                        return GestureDetector(
                          child: Container(
                            padding: const EdgeInsets.all(5.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Container(
                                  width: 90,
                                  height: 75,
                                  child: _buildFilteredWidget(
                                      _filters[index], _thumbnailImageBytes!,
                                      isThumbnail: true),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Text(_filters[index].name,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                )
                              ],
                            ),
                          ),
                          onTap: () => setState(() {
                            _filter = _filters[index];
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<File> saveFilteredImage() async {
    final dir = await PathProvider.getTemporaryDirectory();
    final targetPath =
        "${dir.absolute.path}/temp_${TimeUtils.getTimeString(DateTime.now())}.jpg";
    File imageFile = File(targetPath);

    // Run selected filter on output image
    var outputBytes = await this._filter.apply(_imageBytes!);
    await imageFile.writeAsBytes(outputBytes!);
    return imageFile;
  }

  Widget _buildFilteredWidget(Filter filter, Uint8List imgBytes,
      {bool isThumbnail = false}) {
    var key = filter.name + (isThumbnail ? "thumbnail" : "");
    var data =
        this._cachedFilters.containsKey(key) ? this._cachedFilters[key] : null;
    var isSelected = (filter.name == this._filter.name);

    var createWidget = (Uint8List? bytes) {
      if (isThumbnail) {
        return Container(
          decoration: BoxDecoration(
              color: Colors.grey,
              border: Border.all(
                  color: isSelected ? Colors.blue : Colors.white, width: 3.0),
              borderRadius: const BorderRadius.all(Radius.circular(10.0))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes!, fit: BoxFit.cover)),
        );
      } else
        return Image.memory(
          bytes!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
    };

    if (data == null) {
      var calcFunc = () async {
        return await filter.apply(imgBytes);
      };
      this
          ._queuedApplyFilterFuncList
          .add(MapEntry<String, Future<List<int>?> Function()>(key, calcFunc));
      _runApplyFilterProcess();

      return FutureBuilder<List<int>?>(
        future: _getFilteredData(key),
        builder: (BuildContext context, AsyncSnapshot<List<int>?> snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.done:
              if (snapshot.hasError)
                return Center(child: Text('Error: ${snapshot.error}'));
              return createWidget(snapshot.data as Uint8List?);
            default:
              return const CupertinoActivityIndicator();
          }
        },
      );
    } else {
      return createWidget(data as Uint8List?);
    }
  }

  List<Filter> _getPresetFilters() {
    return <Filter>[
      Filter(name: "no filter"),
      Filter(name: "lighten", matrix: <double>[
        1.5,
        0,
        0,
        0,
        0,
        0,
        1.5,
        0,
        0,
        0,
        0,
        0,
        1.5,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "darken", matrix: <double>[
        .5,
        0,
        0,
        0,
        0,
        0,
        .5,
        0,
        0,
        0,
        0,
        0,
        .5,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "gray on light", matrix: <double>[
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "old times", matrix: <double>[
        1,
        0,
        0,
        0,
        0,
        -0.4,
        1.3,
        -0.4,
        .2,
        -0.1,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "sepia", matrix: <double>[
        0.393,
        0.769,
        0.189,
        0,
        0,
        0.349,
        0.686,
        0.168,
        0,
        0,
        0.272,
        0.534,
        0.131,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "greyscale", matrix: <double>[
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "vintage", matrix: <double>[
        0.9,
        0.5,
        0.1,
        0.0,
        0.0,
        0.3,
        0.8,
        0.1,
        0.0,
        0.0,
        0.2,
        0.3,
        0.5,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0
      ]),
      Filter(name: "filter 1", matrix: <double>[
        0.4,
        0.4,
        -0.3,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.2,
        0.0,
        0.0,
        -1.2,
        0.6,
        0.7,
        1.0,
        0.0
      ]),
      Filter(name: "filter 2", matrix: <double>[
        1.0,
        0.0,
        0.2,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0
      ]),
      Filter(name: "filter 3", matrix: <double>[
        0.8,
        0.5,
        0.0,
        0.0,
        0.0,
        0.0,
        1.1,
        0.0,
        0.0,
        0.0,
        0.0,
        0.2,
        1.1,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0
      ]),
      Filter(name: "filter 4", matrix: <double>[
        1.1,
        0.0,
        0.0,
        0.0,
        0.0,
        0.2,
        1.0,
        -0.4,
        0.0,
        0.0,
        -0.1,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0
      ]),
      Filter(name: "filter 5", matrix: <double>[
        1.2,
        0.1,
        0.5,
        0.0,
        0.0,
        0.1,
        1.0,
        0.05,
        0.0,
        0.0,
        0.0,
        0.1,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0
      ]),
      Filter(name: "elim blue", matrix: <double>[
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        -2,
        1,
        0
      ]),
      Filter(name: "no g red", matrix: <double>[
        1,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "no g magenta", matrix: <double>[
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "lime", matrix: <double>[
        1,
        0,
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        .5,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "purple", matrix: <double>[
        1,
        -0.2,
        0,
        0,
        0,
        0,
        1,
        0,
        -0.1,
        0,
        0,
        1.2,
        1,
        .1,
        0,
        0,
        0,
        1.7,
        1,
        0
      ]),
      Filter(name: "yellow", matrix: <double>[
        1,
        0,
        0,
        0,
        0,
        -0.2,
        1,
        .3,
        .1,
        0,
        -0.1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0
      ]),
      Filter(name: "cyan", matrix: <double>[
        1,
        0,
        0,
        1.9,
        -2.2,
        0,
        1,
        0,
        0,
        .3,
        0,
        0,
        1,
        0,
        .5,
        0,
        0,
        0,
        1,
        .2
      ]),
      // Filter(name: "invert", matrix: <double>[-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]),
    ];
  }
}

class Filter extends Object {
  final String name;
  final List<double> matrix;
  Filter({required this.name, this.matrix = defaultColorMatrix});

  Future<Uint8List?> apply(Uint8List pixels) async {
    final ImageEditorOption option = ImageEditorOption();
    option.addOption(ColorOption(matrix: this.matrix));
    return await ImageEditor.editImage(
        image: pixels, imageEditorOption: option);
  }
}