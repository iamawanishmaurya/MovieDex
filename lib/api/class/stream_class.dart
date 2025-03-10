import 'package:moviedex/api/class/source_class.dart';
import 'package:moviedex/api/class/subtitle_class.dart';

class StreamClass {
  final String language;
  final List<SourceClass> sources;
  final String url;
  final bool isError;
  final List<SubtitleClass>? subtitles;
  final List? animeEpisodes;
  const StreamClass({
    required this.language,
    required this.url,
    this.isError=false,
    required this.sources,
    this.subtitles,
    this.animeEpisodes
  });
}