import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Campus { xitucheng, shahe }

class _CampusPlace {
  const _CampusPlace({
    required this.name,
    required this.category,
    required this.description,
  });

  final String name;
  final String category;
  final String description;
}

const _places = <_Campus, List<_CampusPlace>>{
  _Campus.xitucheng: [
    _CampusPlace(
      name: '西土城校区东门',
      category: '出入口',
      description: '西土城路10号校区东侧入口',
    ),
    _CampusPlace(name: '西土城校区西门', category: '出入口', description: '校园西侧入口'),
    _CampusPlace(name: '主楼', category: '教学与办公', description: '校内主要教学、办公区域'),
    _CampusPlace(name: '图书馆', category: '学习', description: '校内图书馆'),
    _CampusPlace(name: '教三楼', category: '教学与办公', description: '教学楼宇'),
    _CampusPlace(name: '学生食堂', category: '餐饮', description: '校内餐饮区域'),
    _CampusPlace(name: '体育馆', category: '运动', description: '校内体育场馆'),
  ],
  _Campus.shahe: [
    _CampusPlace(name: '沙河校区南门', category: '出入口', description: '南丰路1号校区南侧入口'),
    _CampusPlace(name: '沙河校区西门', category: '出入口', description: '校园西侧入口'),
    _CampusPlace(
      name: '教学实验综合楼',
      category: '教学与办公',
      description: '常见地点包括 S1、S2、S3 等教学与实验楼',
    ),
    _CampusPlace(name: '沙河校区图书馆', category: '学习', description: '图书馆与自习空间'),
    _CampusPlace(name: '雁南园', category: '宿舍', description: '学生宿舍区'),
    _CampusPlace(name: '雁北园', category: '宿舍', description: '学生宿舍区'),
    _CampusPlace(name: '学生食堂', category: '餐饮', description: '校内餐饮区域'),
    _CampusPlace(name: '学生活动中心', category: '活动', description: '学生活动与综合服务区域'),
    _CampusPlace(name: '甲子钟', category: '地标', description: '国脉西路与鸿雁路附近校园地标'),
  ],
};

class CampusMapPage extends StatefulWidget {
  const CampusMapPage({super.key});

  @override
  State<CampusMapPage> createState() => _CampusMapPageState();
}

class _CampusMapPageState extends State<CampusMapPage> {
  _Campus _campus = _Campus.shahe;
  String _query = '';

  String get _campusName => switch (_campus) {
    _Campus.xitucheng => '西土城校区',
    _Campus.shahe => '沙河校区',
  };

  String get _officialMapUrl => switch (_campus) {
    _Campus.xitucheng => 'https://www.bupt.edu.cn/bygk/zjby/xydt.htm',
    _Campus.shahe => 'https://www.bupt.edu.cn/info/1084/78757.htm',
  };

  List<_CampusPlace> get _filteredPlaces {
    final places = _places[_campus]!;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return places;
    return places
        .where(
          (place) =>
              place.name.toLowerCase().contains(query) ||
              place.category.toLowerCase().contains(query) ||
              place.description.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _openMap(String place) async {
    final url = Uri.https('uri.amap.com', 'search', {
      'keyword': '$place $_campusName 北京邮电大学',
      'city': '北京',
      'callnative': '1',
    });
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开地图应用，请稍后重试')));
    }
  }

  Future<void> _openOfficialMap() async {
    final uri = Uri.parse(_officialMapUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时无法打开北邮官方地图')));
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '校区地图',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('搜索校园常用地点；精确位置与步行路线由地图服务提供。'),
          const SizedBox(height: 20),
          SegmentedButton<_Campus>(
            segments: const [
              ButtonSegment(
                value: _Campus.shahe,
                icon: Icon(Icons.location_city),
                label: Text('沙河校区'),
              ),
              ButtonSegment(
                value: _Campus.xitucheng,
                icon: Icon(Icons.apartment),
                label: Text('西土城校区'),
              ),
            ],
            selected: {_campus},
            onSelectionChanged: (value) => setState(() {
              _campus = value.first;
              _query = '';
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('campusMapSearchField'),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索楼宇、食堂、宿舍或地标',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text('打开北邮官方$_campusName平面图'),
              subtitle: const Text('校园平面图来源：北京邮电大学官网'),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openOfficialMap,
            ),
          ),
          const SizedBox(height: 10),
          if (_filteredPlaces.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('没有匹配地点，试试“图书馆”或“食堂”')),
              ),
            )
          else
            ..._filteredPlaces.map(
              (place) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('campusPlace-${place.name}'),
                  leading: CircleAvatar(
                    child: Icon(_placeIcon(place.category)),
                  ),
                  title: Text(place.name),
                  subtitle: Text('${place.category} · ${place.description}'),
                  trailing: const Icon(Icons.directions_outlined),
                  onTap: () => _openMap(place.name),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '地点索引是便捷搜索词，不代表校内测绘坐标；楼宇名称或出入口如有变动，请以校方信息为准。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

IconData _placeIcon(String category) => switch (category) {
  '出入口' => Icons.meeting_room_outlined,
  '教学与办公' => Icons.school_outlined,
  '学习' => Icons.local_library_outlined,
  '餐饮' => Icons.restaurant_outlined,
  '宿舍' => Icons.bed_outlined,
  '运动' => Icons.sports_basketball_outlined,
  '活动' => Icons.groups_outlined,
  _ => Icons.place_outlined,
};
