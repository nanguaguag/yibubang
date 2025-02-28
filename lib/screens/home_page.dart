import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import '../common/app_strings.dart';
import '../screens/choosed_subjects_page.dart';
import '../screens/my_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // 默认主页为题库页
  bool isDownloading = false;
  double downloadProgress = 0.00; // 下载进度
  String statusText = '点击按钮下载题库';
  Map<String, dynamic> updateData = {}; // 更新信息

  @override
  void initState() {
    super.initState();
    // 在界面打开时就开始下载
    downloadAndExtractZip();
  }

  // List of screens corresponding to the tabs
  final List<Widget> _screens = [
    ChoosedSubjectsPage(),
    MyPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<String> calculateMd5(File file) async {
    List<int> fileBytes = await file.readAsBytes();
    return md5.convert(fileBytes).toString();
  }

  Future<bool> needToDownload() async {
    if (updateData.isEmpty) {
      final Uri updateUrl = Uri.parse(
        'https://files.melonhu.cn/yibubang/yibubang_update.json',
      );
      final updateResponse = await http.get(updateUrl);
      if (updateResponse.statusCode != 200) {
        print('请求失败，状态码: ${updateResponse.statusCode}');
        return true;
      }
      // 在这里初始化 更新信息
      updateData = jsonDecode(updateResponse.body);
    }

    String appDocDir = await getDatabasesPath();
    String filePath = '$appDocDir/question_data.sqlite.zip';
    File file = File(filePath);

    if (await file.exists()) {
      String fileMd5 = await calculateMd5(file);
      if (fileMd5 == updateData['latest_data_md5']) {
        return false;
      }
      return true;
    }
    return true;
  }

  Future<void> downloadAndExtractZip() async {
    if (!await needToDownload()) {
      return;
    }

    setState(() {
      isDownloading = true;
      statusText = '正在下载题库...';
      downloadProgress = 0.00; // 初始化进度为0
    });

    // Step 1: Get the document directory
    String appDocDir = await getDatabasesPath();
    String filePath = '$appDocDir/question_data.sqlite.zip';

    // Create a file to store the downloaded ZIP
    File file = File(filePath);

    // Step 2: Download the ZIP file with progress
    final latestDataUrl = updateData['latest_data_url'];
    var request = http.Request('GET', Uri.parse(latestDataUrl));
    var response = await request.send();

    // Step 3: Handle download progress
    int totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    var sink = file.openWrite();

    response.stream.listen(
      (List<int> chunk) {
        // Write each chunk to the file
        sink.add(chunk);
        receivedBytes += chunk.length;

        // Update download progress
        setState(() {
          downloadProgress = receivedBytes / totalBytes;
        });
      },
      onDone: () async {
        // Once download is done, close the sink and proceed with extraction
        await sink.flush();
        await sink.close();

        // Step 4: Extract the ZIP file
        List<int> bytes = await file.readAsBytes();
        Archive archive = ZipDecoder().decodeBytes(bytes);

        // Step 5: Write the extracted files to the documents directory
        // Directory extractedDir = Directory('$appDocDir/extracted');
        // if (!await extractedDir.exists()) {
        //   await extractedDir.create();
        // }

        for (var file in archive) {
          if (file.isFile && !file.name.startsWith('__MACOSX')) {
            String fileName = file.name;
            File extractedFile = File('$appDocDir/$fileName');
            await extractedFile.writeAsBytes(file.content as List<int>);
          }
        }

        setState(() {
          isDownloading = false;
          statusText = '题库下载并解压完成';
        });
      },
      onError: (error) {
        setState(() {
          isDownloading = false;
          statusText = '题库下载失败';
        });
      },
    );
  }

  Widget buildProgress() {
    if (isDownloading) {
      return Column(
        children: [
          CircularProgressIndicator(value: downloadProgress),
          SizedBox(height: 20),
          Text(
            '${(downloadProgress * 100).toStringAsFixed(2)}%',
          ),
        ],
      );
    } else {
      return ElevatedButton(
        onPressed: downloadAndExtractZip,
        child: Text('重新下载'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: needToDownload(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Scaffold(
            appBar: AppBar(
              title: Text('需要下载题库'),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(statusText),
                  SizedBox(height: 20),
                  buildProgress(),
                ],
              ),
            ),
          );
        } else {
          return Scaffold(
            body: _screens[_selectedIndex],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.book),
                  label: AppStrings.selectedSubjectsTitle,
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: AppStrings.myPageTitle,
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
