import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth.dart';
import '../theme/app.dart';
import 'login.dart';

const List<String> _kNamaBulan = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

class PendapatanEntry {
  final int idPendapatan;
  final int idKantor;
  final String namaKantor;
  final int idJenis;
  final String namaJenis;
  final int tahun;
  final int bulan;
  final double nominal;

  PendapatanEntry({
    required this.idPendapatan,
    required this.idKantor,
    required this.namaKantor,
    required this.idJenis,
    required this.namaJenis,
    required this.tahun,
    required this.bulan,
    required this.nominal,
  });

  String get namaBulan =>
      (bulan >= 1 && bulan <= 12) ? _kNamaBulan[bulan - 1] : 'Bulan $bulan';

  factory PendapatanEntry.fromMap(Map<String, dynamic> map) {
    final kantor = map['kantor'] as Map<String, dynamic>?;
    final jenis = map['jenis_pinjaman'] as Map<String, dynamic>?;
    return PendapatanEntry(
      idPendapatan: (map['id_pendapatan'] as num).toInt(),
      idKantor: (map['id_kantor'] as num).toInt(),
      namaKantor: (kantor?['nama_kantor'] as String?) ?? 'Kantor tidak diketahui',
      idJenis: (map['id_jenis'] as num).toInt(),
      namaJenis: (jenis?['nama_jenis'] as String?) ?? 'Jenis tidak diketahui',
      tahun: (map['tahun'] as num).toInt(),
      bulan: (map['bulan'] as num).toInt(),
      nominal: (map['nominal'] as num).toDouble(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  String? _selectedFileName;
  bool _isProcessing = false;
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedPeriod = 6;

  List<PendapatanEntry> _loans = [];
  int _kantorCount = 0;

  Map<String, int> _kantorIdByName = {};
  Map<String, int> _jenisIdByName = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double get _total => _loans.fold(0.0, (sum, row) => sum + row.nominal);

  double get _rataRata => _loans.isEmpty ? 0 : _total / _loans.length;

  String _formatNumber(double value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}.',
      );

  String _formatCompact(double value) {
    if (value >= 1000000000) {
      return 'Rp ${(value / 1000000000).toStringAsFixed(2)} M';
    }
    if (value >= 1000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(0)} Jt';
    }
    return 'Rp ${_formatNumber(value)}';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // Load Database
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('pendapatan')
            .select(
              'id_pendapatan, id_kantor, id_jenis, tahun, bulan, nominal, '
              'kantor(nama_kantor, wilayah), jenis_pinjaman(nama_jenis, kategori)',
            )
            .order('tahun', ascending: true)
            .order('bulan', ascending: true),
        _supabase.from('kantor').select('id_kantor, nama_kantor'),
        _supabase.from('jenis_pinjaman').select('id_jenis, nama_jenis'),
      ]);

      final pendapatanRows = results[0] as List<dynamic>;
      final kantorRows = results[1] as List<dynamic>;
      final jenisRows = results[2] as List<dynamic>;

      final loans = pendapatanRows
          .map((row) => PendapatanEntry.fromMap(row as Map<String, dynamic>))
          .toList();

      final kantorIdByName = <String, int>{
        for (final row in kantorRows)
          (row['nama_kantor'] as String): (row['id_kantor'] as num).toInt(),
      };
      final jenisIdByName = <String, int>{
        for (final row in jenisRows)
          (row['nama_jenis'] as String): (row['id_jenis'] as num).toInt(),
      };

      if (!mounted) return;
      setState(() {
        _loans = loans;
        _kantorCount = kantorRows.length;
        _kantorIdByName = kantorIdByName;
        _jenisIdByName = jenisIdByName;
        _isLoading = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data: ${error.message}';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memuat data: $error';
        _isLoading = false;
      });
    }
  }

  // CHART & RANKING
  List<MapEntry<String, double>> get _trenPeriode {
    final byPeriode = <String, double>{};
    final order = <String>[];
    for (final loan in _loans) {
      final key = '${loan.tahun}-${loan.bulan.toString().padLeft(2, '0')}';
      if (!byPeriode.containsKey(key)) {
        order.add(key);
        byPeriode[key] = 0;
      }
      byPeriode[key] = byPeriode[key]! + loan.nominal;
    }
    final entries = order.map((key) => MapEntry(key, byPeriode[key]!)).toList();
    if (entries.length <= _selectedPeriod) return entries;
    return entries.sublist(entries.length - _selectedPeriod);
  }

  String _labelPeriode(String key) {
    final parts = key.split('-');
    final bulan = int.parse(parts[1]);
    return (bulan >= 1 && bulan <= 12)
        ? _kNamaBulan[bulan - 1].substring(0, 3)
        : key;
  }

  List<MapEntry<String, double>> get _rankingKantor {
    final byKantor = <String, double>{};
    for (final loan in _loans) {
      byKantor[loan.namaKantor] = (byKantor[loan.namaKantor] ?? 0) + loan.nominal;
    }
    final entries = byKantor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).toList();
  }

  // Export / Import
  Future<void> _exportExcel() async {
    if (_loans.isEmpty) {
      _showMessage('Belum ada data untuk diekspor', error: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Data Pinjaman'];
      sheet.appendRow(
        [
          'Tahun',
          'Bulan',
          'Kantor',
          'Jenis Pinjaman',
          'Nominal (Rp)',
        ].map(TextCellValue.new).toList(),
      );
      for (final row in _loans) {
        sheet.appendRow([
          IntCellValue(row.tahun),
          TextCellValue(row.namaBulan),
          TextCellValue(row.namaKantor),
          TextCellValue(row.namaJenis),
          DoubleCellValue(row.nominal),
        ]);
      }
      final bytes = excel.save();
      if (bytes == null) throw StateError('Gagal membuat berkas Excel');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/fundmonitor_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Data FundMonitor (Excel)',
        ),
      );
    } catch (error) {
      _showMessage('Export Excel gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_loans.isEmpty) {
      _showMessage('Belum ada data untuk diekspor', error: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Text(
              'Laporan FundMonitor',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Total pinjaman aktif: Rp ${_formatNumber(_total)}'),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Tahun', 'Bulan', 'Kantor', 'Jenis', 'Nominal (Rp)'],
              data: _loans
                  .map(
                    (row) => [
                      '${row.tahun}',
                      row.namaBulan,
                      row.namaKantor,
                      row.namaJenis,
                      _formatNumber(row.nominal),
                    ],
                  )
                  .toList(),
            ),
          ],
        ),
      );
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/fundmonitor_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await document.save(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Laporan FundMonitor (PDF)',
        ),
      );
    } catch (error) {
      _showMessage('Export PDF gagal: $error', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _importExcel() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result.isEmpty) return;
    final selectedFile = result.single;
    setState(() {
      _selectedFileName = selectedFile.name;
      _isProcessing = true;
    });
    try {
      final sheet = Excel.decodeBytes(await selectedFile.readAsBytes())
          .tables
          .values
          .first;

      final rowsToInsert = <Map<String, dynamic>>[];
      final skipped = <String>[];

      for (final row in sheet.rows.skip(1)) {
        if (row.length < 5) continue;
        final values =
            row.map((cell) => cell?.value.toString().trim() ?? '').toList();
        if (values.take(5).any((value) => value.isEmpty)) continue;

        final tahun = int.tryParse(values[0]);
        final bulan = _parseBulan(values[1]);
        final idKantor = _kantorIdByName[values[2]];
        final idJenis = _jenisIdByName[values[3]];
        final nominal = double.tryParse(values[4].replaceAll(RegExp(r'[^0-9.]'), ''));

        if (tahun == null || bulan == null || idKantor == null ||
            idJenis == null || nominal == null) {
          skipped.add(values.join(', '));
          continue;
        }

        rowsToInsert.add({
          'id_kantor': idKantor,
          'id_jenis': idJenis,
          'tahun': tahun,
          'bulan': bulan,
          'nominal': nominal,
        });
      }

      if (rowsToInsert.isEmpty) {
        throw const FormatException(
          'Tidak ada baris valid. Pastikan kolom Kantor & Jenis Pinjaman '
          'sesuai data di master (Kantor / Jenis Pinjaman).',
        );
      }

      await _supabase.from('pendapatan').insert(rowsToInsert);
      await _loadData();

      final message = skipped.isEmpty
          ? '${rowsToInsert.length} baris berhasil diimpor'
          : '${rowsToInsert.length} baris diimpor, ${skipped.length} baris dilewati (tidak valid)';
      _showMessage(message);
    } catch (error) {
      _showMessage(
        'Import Excel gagal: format file tidak sesuai ($error)',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  int? _parseBulan(String value) {
    final asNumber = int.tryParse(value);
    if (asNumber != null && asNumber >= 1 && asNumber <= 12) return asNumber;
    final index = _kNamaBulan.indexWhere(
      (nama) => nama.toLowerCase() == value.toLowerCase(),
    );
    return index == -1 ? null : index + 1;
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('FundMonitor'),
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadData,
          icon: const Icon(Icons.refresh),
          tooltip: 'Muat ulang data',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          tooltip: 'Keluar',
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.apartment_outlined),
          label: 'Kantor',
        ),
        NavigationDestination(
          icon: Icon(Icons.credit_score_outlined),
          label: 'Pinjaman',
        ),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Akun'),
      ],
    ),
    body: SafeArea(child: _buildBody()),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ringkasan Eksekutif',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            _summaryCard(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    Icons.apartment,
                    'Jaringan Kantor',
                    '$_kantorCount Unit Aktif',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    Icons.account_balance_wallet,
                    'Rata-rata Pinjaman',
                    _formatCompact(_rataRata),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _chartCard(),
            const SizedBox(height: 16),
            _actionCard(),
            const SizedBox(height: 16),
            _rankingCard(),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL PINJAMAN AKTIF',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Rp ${_formatNumber(_total)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_loans.length} transaksi tercatat',
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );

  Widget _statCard(IconData icon, String title, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.secondary),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chartCard() {
    final tren = _trenPeriode;
    final maxValue = tren.isEmpty
        ? 1.0
        : tren.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tren Penyaluran',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                DropdownButton<int>(
                  value: _selectedPeriod,
                  items: const [3, 6, 12]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value Bulan'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPeriod = value!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (tren.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Belum ada data untuk periode ini',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              )
            else
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: tren.map((entry) {
                    final height = (entry.value / maxValue * 110)
                        .clamp(20, 110)
                        .toDouble();
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: height,
                            width: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _labelPeriode(entry.key),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tindakan & Laporan Data',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _exportExcel,
                  icon: const Icon(Icons.table_view),
                  label: const Text('Export Excel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _importExcel,
            icon: const Icon(Icons.upload_file),
            label: Text(_selectedFileName ?? 'Import data dari Excel'),
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );

  Widget _rankingCard() {
    final ranking = _rankingKantor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ranking Penyaluran',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            if (ranking.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada data pinjaman',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ...ranking.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: entry.key == 0
                        ? AppColors.primary
                        : AppColors.surfaceContainer,
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(
                        color:
                            entry.key == 0 ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                  title: Text(entry.value.key),
                  trailing: Text(
                    _formatCompact(entry.value.value),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}