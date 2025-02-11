import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moviedex/api/class/stream_class.dart';
import 'package:moviedex/components/episode_list_player.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
// web imports
// import 'dart:html' as html;

class ContentPlayer extends StatefulWidget {
  final List<StreamClass> streams;
  final String contentType;
  final int? currentEpisode;
  final String title;  // Add this
  const ContentPlayer({
    super.key, 
    required this.streams, 
    required this.contentType, 
    this.currentEpisode,
    required this.title,  // Add this
  });

  @override
  State<ContentPlayer> createState() => _ContentPlayerState();
}

class _ContentPlayerState extends State<ContentPlayer> with TickerProviderStateMixin {
  late VideoPlayerController _controller;
  late Timer _hideTimer;
  bool _isPlaying = false;
  bool _isCountrollesVisible = true;
  bool _isFullScreen = false;
  bool _isSettingsVisible = false;
  bool _isEpisodesVisible = false;
  bool _isBuffering = false;
  String _currentQuality = 'Auto';
  String _currentLanguage = 'original';
  String _settingsPage = 'main';
  Duration? _duration;
  Duration? _position;
  var _progress = 0.0;
  var _bufferingProgress = 0.0;
  List settingElements = ["Quality", "Language", "Speed"];
  bool _showForwardIndicator = false;
  bool _showRewindIndicator = false;
  late AnimationController _seekAnimationController;
  late Animation<double> _seekIconAnimation;
  late Animation<double> _seekTextAnimation;
  bool _isDraggingSlider = false;
  double _dragProgress = 0.0;

  late TransformationController _transformationController;
  late AnimationController _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  bool _isZoomed = false;
  final double _maxScale = 3.0;

  // Add new variables for double tap
  Timer? _doubleTapTimer;

  // Add these new variables
  int _consecutiveTaps = 0;
  Timer? _consecutiveTapTimer;
  bool _isShowingSeekIndicator = false;

  // Add new variables for playback speed
  double _playbackSpeed = 1.0;
  final List<Map<String, dynamic>> _speedOptions = [
    {'label': '0.25x', 'value': 0.25},
    {'label': '0.5x', 'value': 0.5},
    {'label': '0.75x', 'value': 0.75},
    {'label': 'Normal', 'value': 1.0},
    {'label': '1.25x', 'value': 1.25},
    {'label': '1.5x', 'value': 1.5},
    {'label': '1.75x', 'value': 1.75},
    {'label': '2x', 'value': 2.0},
  ];

  // Add new variable for initialization state
  bool _isInitialized = false;

  // Add new animation controllers
  late AnimationController _forwardAnimationController;
  late AnimationController _rewindAnimationController;
  late Animation<double> _forwardRotation;
  late Animation<double> _rewindRotation;

  // Add new animation controllers for double tap indicators
  late AnimationController _seekForwardAnimationController;
  late AnimationController _seekRewindAnimationController;
  late Animation<double> _seekForwardRotation;
  late Animation<double> _seekRewindRotation;
  
  String getSourceOfQuality(StreamClass data){
    final source = data.sources.where((source)=>source.quality==_currentQuality).toList();
    if(source.isEmpty){
      _currentQuality = 'Auto';
      return data.url;
    }else{
      return source[0].url;
    }
  }

  void _onControllerUpdate() async {
    if (!mounted || !_controller.value.isInitialized || _isDraggingSlider) return;

    // Get current video state
    final duration = _controller.value.duration;
    final position = _controller.value.position;
    final isPlaying = _controller.value.isPlaying;
    final isBuffering = _controller.value.isBuffering;

    // Only update if position or duration changed
    if (_position != position || _duration != duration) {
      setState(() {
        _duration = duration;
        _position = position;
        _isPlaying = isPlaying;
        _isBuffering = isBuffering;
        
        // Calculate progress
        if (duration.inMilliseconds > 0) {
          _progress = position.inMilliseconds / duration.inMilliseconds;
        }
      });
    }

    // Update buffer progress
    if (_controller.value.buffered.isNotEmpty) {
      final bufferedEnd = _controller.value.buffered.last.end;
      if (mounted) {
        setState(() {
          _bufferingProgress = bufferedEnd.inMilliseconds / duration.inMilliseconds;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addStatusListener(_onZoomAnimationStatus);
    String videoUrl = widget.streams[0].url;
    _currentLanguage = widget.streams[0].language;
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _controller.addListener(_onControllerUpdate);
          _controller.play();
        });
      });
    _startHideTimer();

    // Add periodic position update
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (mounted && _controller.value.isInitialized) {
        _onControllerUpdate();
      }
    });

    _seekAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _seekIconAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _seekAnimationController,
      curve: Curves.easeOut,
    ));

    _seekTextAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _seekAnimationController,
      curve: Curves.easeOut,
    ));

    // Initialize seek button animations
    _forwardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _rewindAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _forwardRotation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _forwardAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _rewindRotation = Tween(begin: 0.0, end: -1.0).animate(
      CurvedAnimation(
        parent: _rewindAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Initialize seek indicator animations
    _seekForwardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _seekRewindAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _seekForwardRotation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seekForwardAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _seekRewindRotation = Tween(begin: 0.0, end: -1.0).animate(
      CurvedAnimation(
        parent: _seekRewindAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    _transformationController.dispose();
    _seekAnimationController.dispose();
    _doubleTapTimer?.cancel();
    _consecutiveTapTimer?.cancel();
    _controller.dispose();
    _hideTimer.cancel();
    _forwardAnimationController.dispose();
    _rewindAnimationController.dispose();
    _seekForwardAnimationController.dispose();
    _seekRewindAnimationController.dispose();
    super.dispose();
  }

  void _onZoomAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _zoomAnimation?.removeListener(_onZoomAnimation);
      _zoomAnimation = null;
      _zoomAnimationController.reset();
    }
  }

  void _onZoomAnimation() {
    if (_zoomAnimation != null) {
      _transformationController.value = _zoomAnimation!.value;
    }
  }

  void _handleZoomReset() {
    _isZoomed = false;
    final Matrix4 current = _transformationController.value;
    _zoomAnimation = Matrix4Tween(
      begin: current,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _zoomAnimationController,
      curve: Curves.easeOutExpo,
    ));
    _zoomAnimation!.addListener(_onZoomAnimation);
    _zoomAnimationController.forward();
    _currentScale = 1.0;
    _baseScale = 1.0;
  }

  void _handleZoomUpdate(ScaleUpdateDetails details) {
    if (_zoomAnimationController.isAnimating) return;

    final double newScale = (_baseScale * details.scale).clamp(1.0, _maxScale);
    
    if (newScale == 1.0 && _currentScale != 1.0) {
      _handleZoomReset();
      return;
    }

    setState(() {
      _currentScale = newScale;
      _isZoomed = _currentScale > 1.0;

      // Calculate the focal point for zooming
      final Offset centerOffset = details.localFocalPoint;
      final Matrix4 matrix = Matrix4.identity()
        ..translate(centerOffset.dx, centerOffset.dy)
        ..scale(_currentScale)
        ..translate(-centerOffset.dx, -centerOffset.dy);

      _transformationController.value = matrix;
    });
  }

  void _handleZoomEnd(ScaleEndDetails details) {
    _baseScale = _currentScale;
    if (_currentScale <= 1.1) {
      _handleZoomReset();
    }
  }

  void _startHideTimer() {
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!_isSettingsVisible && !_isEpisodesVisible) {  // Only hide if menus are closed
        setState(() {
          _isCountrollesVisible = false;
        });
      }
    });
  }

  void _cancelAndRestartHideTimer() {
    _hideTimer.cancel();
    _isCountrollesVisible = true;
    _startHideTimer();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        // Enable true fullscreen including notch area
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      } else {
        // Return to normal mode
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ).then((_) {
          SystemChrome.setSystemUIOverlayStyle(
            const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            ),
          );
        });
      }
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    });
  }

  void _toggleSettingsMenu() {
    setState(() {
      _isSettingsVisible = !_isSettingsVisible;
      _settingsPage = 'main';
      _cancelAndRestartHideTimer();
    });
  }

  void _toggleEpisodesMenu() {
    setState(() {
      _isEpisodesVisible = !_isEpisodesVisible;
      _cancelAndRestartHideTimer();
    });
  }

  void _showSettingsOptions(String page) {
    setState(() {
      _settingsPage = page;
      _cancelAndRestartHideTimer();
    });
  }

  void _handleSettingsBack() {
    setState(() {
      if (_settingsPage == 'main') {
        _isSettingsVisible = false;
      } else {
        _settingsPage = 'main';
      }
      _cancelAndRestartHideTimer();
    });
  }

  void _selectQuality(String quality, String url) {
    setState(() {
      if (_currentQuality != quality) {
        _controller.dispose();
        _currentQuality = quality;
        _controller = VideoPlayerController.networkUrl(Uri.parse(url))
          ..initialize().then((_) {
            setState(() {
              _controller.addListener(_onControllerUpdate);
              _controller.play();
            });
          });
        _isSettingsVisible = false;
      }
    });
  }

  void _selectLanguage(StreamClass data) {
    setState(() {
      if (_currentLanguage != data.language) {
        _controller.dispose();
        _currentLanguage = data.language;
        _controller = VideoPlayerController.networkUrl(Uri.parse(_currentQuality == 'Auto' ? data.url : getSourceOfQuality(data)))
          ..initialize().then((_) {
            setState(() {
              _controller.addListener(_onControllerUpdate);
              _controller.play();
            });
          });
        _isSettingsVisible = false;
      }
    });
  }

  void _selectSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
      _controller.setPlaybackSpeed(speed);
      _isSettingsVisible = false;
    });
  }

  void _handleTap() {
    setState(() {
        _isCountrollesVisible = !_isCountrollesVisible;
        if (_isCountrollesVisible) {
          _cancelAndRestartHideTimer();
        }
    });
  }


  void _handleDoubleTapSeek(BuildContext context, TapDownDetails details) {
    if (!_controller.value.isInitialized) return;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition.dx;
    
    setState(() {
      _consecutiveTaps++;
      _isShowingSeekIndicator = true;
      _isCountrollesVisible = false;
      
      if (tapPosition < screenWidth * 0.5) {
        // Left side - Rewind
        _showRewindIndicator = true;
        _seekRewindAnimationController
          ..reset()
          ..forward();
        _seekRelative(-10 * _consecutiveTaps);
      } else {
        // Right side - Forward
        _showForwardIndicator = true;
        _seekForwardAnimationController
          ..reset()
          ..forward();
        _seekRelative(10 * _consecutiveTaps);
      }
    });

    _consecutiveTapTimer?.cancel();
    _consecutiveTapTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _consecutiveTaps = 0;
        _showRewindIndicator = false;
        _showForwardIndicator = false;
        _isShowingSeekIndicator = false;
      });
    });
  }


  void _seekRelative(int seconds) async {
    if (!_controller.value.isInitialized) return;

    final currentPosition = _controller.value.position;
    final duration = _controller.value.duration;
    final newPosition = currentPosition + Duration(seconds: seconds);

    // Ensure we don't seek beyond bounds
    if (newPosition < Duration.zero) {
      await _controller.seekTo(Duration.zero);
    } else if (newPosition > duration) {
      await _controller.seekTo(duration);
    } else {
      await _controller.seekTo(newPosition);
    }

    // Update progress after seeking
    setState(() {
      _position = _controller.value.position;
      _progress = _position!.inMilliseconds / duration.inMilliseconds;
    });
  }

  void _togglePlayPause() {
    if (_isBuffering) return;
    setState(() {
      if (_isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _isPlaying = !_isPlaying;
      _isCountrollesVisible = true;
      _cancelAndRestartHideTimer();
    });
  }


  void _handleProgressChanged(double value) {
    if (!_controller.value.isInitialized) return;

    setState(() {
      _isDraggingSlider = true;
      _dragProgress = value;
      _progress = value; // Update visual progress
      final duration = _controller.value.duration;
      _position = Duration(milliseconds: (duration.inMilliseconds * value).round());
    });
  }

  void _handleProgressChangeEnd(double value) {
    if (!_controller.value.isInitialized) return;
    
    final duration = _controller.value.duration;
    final position = Duration(milliseconds: (duration.inMilliseconds * value).round());
    
    _controller.seekTo(position).then((_) {
      setState(() {
        _isDraggingSlider = false;
        _progress = value;
        _position = position;
      });
    });
    
    _cancelAndRestartHideTimer();
  }

  Widget _buildSettingsMenu() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      right: _isSettingsVisible ? 0 : -250, // Changed from right to left
      top: 0,
      bottom: 0,
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft, // Changed direction
            end: Alignment.centerRight,
            colors: [
              Colors.black.withOpacity(0.95),
              Colors.black.withOpacity(0.8),
              Colors.black.withOpacity(0.6),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _settingsPage == 'main' ? Icons.close : Icons.arrow_back,
                      color: Colors.white,
                    ),
                    onPressed: _handleSettingsBack,
                  ),
                  Text(
                    _settingsPage == 'main' ? 'Settings' 
                    : _settingsPage == 'quality' ? 'Quality' 
                    : _settingsPage == 'language' ? 'Language'
                    : 'Speed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: _settingsPage == 'main'
                    ? Column(
                        children: settingElements.map((element) => 
                          ListTile(
                            onTap: () => _showSettingsOptions(element.toLowerCase()),
                            title: Text(
                              element,
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  element == 'Quality' ? _currentQuality 
                                  : element == 'Language' ? _currentLanguage
                                  : _playbackSpeed == 1.0 ? 'Normal' : '${_playbackSpeed}x',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.7)),
                              ],
                            ),
                          ),
                        ).toList(),
                      )
                    : Column(
                        children: _settingsPage == 'quality'
                            ? [
                                _buildOptionTile('Auto', _currentQuality == 'Auto'),
                                ...widget.streams[0].sources
                                    .where((source) => source.quality != 'Auto')
                                    .map((source) => _buildOptionTile(
                                        '${source.quality}p',
                                        _currentQuality == source.quality,
                                        () => _selectQuality(source.quality, source.url)))
                              ]
                            : _settingsPage == 'language'
                            ? widget.streams
                                .map((stream) => _buildOptionTile(
                                    stream.language,
                                    _currentLanguage == stream.language,
                                    () => _selectLanguage(stream)))
                                .toList()
                            : _speedOptions.map((option) => ListTile(
                                onTap: () => _selectSpeed(option['value']),
                                title: Text(
                                  option['label'],
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: _playbackSpeed == option['value']
                                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                                    : null,
                                selected: _playbackSpeed == option['value'],
                                selectedTileColor: Colors.white.withOpacity(0.1),
                              )).toList(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(String title, bool isSelected, [Function()? onTap]) {
    return ListTile(
      onTap: onTap,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      selected: isSelected,
      selectedTileColor: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, [bool isForward = true]) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onPressed();
          if (isForward) {
            _forwardAnimationController.forward(from: 0.0);
          } else {
            _rewindAnimationController.forward(from: 0.0);
          }
          _cancelAndRestartHideTimer();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
          child: RotationTransition(
            turns: isForward ? _forwardRotation : _rewindRotation,
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          Icons.replay_10_rounded,
          () => _seekRelative(-10),
          false
        ),
        const SizedBox(width: 32),
        _buildPlayPauseButton(),
        const SizedBox(width: 32),
        _buildControlButton(
          Icons.forward_10_rounded,
          () => _seekRelative(10),
          true
        ),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _isCountrollesVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.7),
            ],
            stops: const [0.0, 0.2, 0.8, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildTopBar(),
            if (!_isInitialized) 
              _buildLoadingIndicator()
            else
              _buildControlsRow(),
            _buildProgressBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            _formatDuration(_position ?? Duration.zero),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Colors.white.withOpacity(0.2),
                    thumbColor: Theme.of(context).colorScheme.primary,
                    overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Buffer progress
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: LinearProgressIndicator(
                          value: _bufferingProgress,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.3)
                          ),
                          minHeight: 4,
                        ),
                      ),
                      // Playback progress
                      if (_isInitialized)
                        Slider(
                          value: _isDraggingSlider ? _dragProgress.clamp(0.0, 1.0) : _progress.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          onChanged: _handleProgressChanged,
                          onChangeEnd: _handleProgressChangeEnd,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatDuration(_duration ?? Duration.zero),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            color: Colors.white,
            iconSize: 24,
          ),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isZoomed)
            _buildZoomIndicator(),
          if (widget.contentType == 'tv')
            IconButton(
              onPressed: _toggleEpisodesMenu,
              icon: const Icon(Icons.playlist_play_rounded),
              iconSize: 32,
              color: Colors.white,
            ),
          IconButton(
            onPressed: _toggleSettingsMenu,
            icon: const Icon(Icons.settings),
            iconSize: 28,
            color: Colors.white,
          ),
          if (Theme.of(context).platform != TargetPlatform.android && 
              Theme.of(context).platform != TargetPlatform.iOS)
            IconButton(
              onPressed: _toggleFullScreen,
              icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
              iconSize: 28,
              color: Colors.white,
            ),
        ],
      ),
    );
  }

  Widget _buildTapOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Left tap area
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.5,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: (details) {
                if (!_isSettingsVisible && !_isEpisodesVisible) {
                  _handleDoubleTapSeek(context, details);
                }
              },
              onDoubleTap: () {},
              onTap: _handleTap,
            ),
          ),
          // Right tap area
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.5,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: (details) {
                if (!_isSettingsVisible && !_isEpisodesVisible) {
                  _handleDoubleTapSeek(context, details);
                }
              },
              onDoubleTap: () {},
              onTap: _handleTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    if (_isBuffering) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 2,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: InkWell(
          onTap: _togglePlayPause,
          borderRadius: BorderRadius.circular(28),
          child: Icon(
            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Video Layer
          Center(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: _maxScale,
              onInteractionUpdate: _handleZoomUpdate,
              onInteractionEnd: _handleZoomEnd,
              clipBehavior: Clip.none,
              panEnabled: _isZoomed,
              scaleEnabled: true,
              child: AspectRatio(
                aspectRatio: MediaQuery.of(context).size.width / MediaQuery.of(context).size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          ),

          _buildTapOverlay(),

          Stack(
            children: [
              // Controls overlay with animation
              AnimatedOpacity(
                opacity: _isCountrollesVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Stack(
                  children: [
                    // Background when controls are visible
                    if (_isCountrollesVisible)
                      Container(color: Colors.black.withOpacity(0.3)),

                    // Controls
                    if (_isCountrollesVisible)
                      GestureDetector(
                        onTap: _handleTap,
                        onDoubleTapDown: (details) => _handleDoubleTapSeek(context, details),
                        child: _buildControlsOverlay(),
                      ),
                  ],
                ),
              ),

              // Settings menu (separate opacity animation)
              _buildSettingsMenu(),

              // Episodes menu (separate opacity animation)
              _isEpisodesVisible
                  ? Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: EpisodeListForPlayer(
                        currentEpisode: widget.currentEpisode,
                        onEpisodeSelected: (episode) {
                          setState(() => _isEpisodesVisible = false);
                        },
                      ),
                    )
                  : const SizedBox(),
            ],
          ),

          // Seek Indicators (always on top)
          if (_showRewindIndicator || _showForwardIndicator)
            _buildSeekIndicators(),
        ],
      ),
    );
  }

  Widget _buildSeekIndicators() {
    return Row(
      children: [
        Expanded(
          child: AnimatedOpacity(
            opacity: _showRewindIndicator ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _buildSeekIndicator(Icons.replay_10, "-10s", true),
          ),
        ),
        SizedBox(width: MediaQuery.of(context).size.width * 0.2),
        Expanded(
          child: AnimatedOpacity(
            opacity: _showForwardIndicator ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _buildSeekIndicator(Icons.forward_10, "+10s", false),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekIndicator(IconData icon, String text, bool isForward) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: isForward ? _seekForwardRotation : _seekRewindRotation,
              child: Icon(
                icon,
                color: Colors.white,
                size: 45,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_consecutiveTaps * 10}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      top: 16,
      right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isZoomed ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_in, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                '${(_currentScale * 100).toInt()}%',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}