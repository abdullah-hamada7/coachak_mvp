import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/api/api_client.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';

class FoodLogScreen extends ConsumerStatefulWidget {
  const FoodLogScreen({super.key});

  @override
  ConsumerState<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends ConsumerState<FoodLogScreen> {
  Map<String, dynamic>? _analysis;
  bool _loading = false;
  String _mealType = 'lunch';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(subscriptionProvider.notifier).refresh();
    });
  }

  List<Map<String, dynamic>> _sanitizeItems(List<dynamic> rawItems) {
    return rawItems.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      var confidence = item['confidence'];
      if (confidence is num && confidence > 1) {
        confidence = confidence / 100;
      }
      return {
        'name': (item['name']?.toString().trim().isNotEmpty == true)
            ? item['name'].toString().trim()
            : 'Meal',
        'portion_estimate': item['portion_estimate']?.toString() ?? '1 serving',
        'confidence': (confidence as num?)?.toDouble() ?? 1.0,
        if (item['calories'] != null) 'calories': (item['calories'] as num).toDouble(),
        if (item['protein_g'] != null) 'protein_g': (item['protein_g'] as num).toDouble(),
        if (item['carbs_g'] != null) 'carbs_g': (item['carbs_g'] as num).toDouble(),
        if (item['fat_g'] != null) 'fat_g': (item['fat_g'] as num).toDouble(),
        if (item['usda_fdc_id'] != null) 'usda_fdc_id': (item['usda_fdc_id'] as num).toInt(),
      };
    }).toList();
  }

  Future<void> _submitLog({
    required String mealType,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      _showMessage('Add at least one food item to log.');
      return;
    }

    try {
      await ref.read(apiClientProvider).logFood({
        'meal_type': mealType,
        'items': items,
      });
      if (!mounted) return;
      _showMessage('Meal logged! +20 XP');
      setState(() => _analysis = null);
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        _showMessage('Session expired. Please sign in again.');
      } else if (e.response?.statusCode == 422) {
        _showMessage('Could not save meal. Check the food details and try again.');
      } else {
        _showMessage('Log failed: ${e.message ?? 'network error'}');
      }
    } catch (e) {
      if (mounted) _showMessage('Log failed: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, maxWidth: 1024);
    if (image == null) return;

    setState(() {
      _loading = true;
      _analysis = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.analyzeFood(image.path);
      setState(() => _analysis = result);
      ref.invalidate(subscriptionProvider);
    } on DioException catch (e) {
      if (e.response?.statusCode == 402 && mounted) {
        await showSubscriptionLimitPrompt(context, ref, SubscriptionLimitException.fromDio(e));
      } else if (mounted) {
        _showMessage('Analysis failed. Try quick manual log instead.');
      }
    } catch (_) {
      if (mounted) _showMessage('Analysis failed. Try quick manual log instead.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmLog() async {
    if (_analysis == null) return;
    final items = _sanitizeItems((_analysis!['items'] as List?) ?? []);
    await _submitLog(mealType: _mealType, items: items);
  }

  Future<void> _showQuickLogDialog() async {
    final nameController = TextEditingController();
    final calController = TextEditingController();
    final proteinController = TextEditingController();
    final carbsController = TextEditingController();
    final fatController = TextEditingController();
    var selectedMeal = _mealType;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Quick Log Meal'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedMeal,
                      decoration: const InputDecoration(labelText: 'Meal Type'),
                      items: ['breakfast', 'lunch', 'dinner', 'snack']
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase())))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedMeal = v ?? selectedMeal),
                    ),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Food / Meal Name'),
                    ),
                    TextField(
                      controller: calController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: proteinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Protein (g)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: carbsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Carbs (g)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: fatController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Fat (g)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter a food or meal name')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    await _submitLog(
                      mealType: selectedMeal,
                      items: [
                        {
                          'name': name,
                          'portion_estimate': '1 serving',
                          'confidence': 1.0,
                          'calories': double.tryParse(calController.text) ?? 0,
                          'protein_g': double.tryParse(proteinController.text) ?? 0,
                          'carbs_g': double.tryParse(carbsController.text) ?? 0,
                          'fat_g': double.tryParse(fatController.text) ?? 0,
                        },
                      ],
                    );
                  },
                  child: const Text('Log Meal'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider).valueOrNull;
    final unlimitedScans = subscription?.isUnlimited('food_scans') ?? false;
    final scanLimit = subscription?.limitFor('food_scans');
    final scanUsed = subscription?.usedFor('food_scans') ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Food Log')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            unlimitedScans
                ? 'Unlimited meal logging and photo scans on your plan.'
                : 'Manual logging is always unlimited — photo scan limits apply separately.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (!unlimitedScans && scanLimit != null && scanLimit > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Photo scans: $scanUsed / $scanLimit this month',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _showQuickLogDialog,
            icon: const Icon(Icons.edit_note),
            label: const Text('Quick Manual Log'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : () => _pickAndAnalyze(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickAndAnalyze(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_analysis != null) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: 'Meal Type'),
              items: ['breakfast', 'lunch', 'dinner', 'snack']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _mealType = v!),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detected Items', style: Theme.of(context).textTheme.titleMedium),
                    ...((_analysis!['items'] as List?) ?? []).map((item) {
                      final i = item as Map<String, dynamic>;
                      return ListTile(
                        title: Text(i['name']?.toString() ?? ''),
                        subtitle: Text('${i['portion_estimate']}'),
                        trailing: Text('${i['calories']?.toStringAsFixed(0) ?? '?'} cal'),
                      );
                    }),
                    const Divider(),
                    Text('Total: ${_analysis!['total_calories']?.toStringAsFixed(0) ?? 0} cal'),
                    Text('P: ${_analysis!['total_protein_g']?.toStringAsFixed(0) ?? 0}g | '
                        'C: ${_analysis!['total_carbs_g']?.toStringAsFixed(0) ?? 0}g | '
                        'F: ${_analysis!['total_fat_g']?.toStringAsFixed(0) ?? 0}g'),
                    if (_analysis!['notes'] != null) Text(_analysis!['notes'].toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _confirmLog, child: const Text('Confirm & Log')),
          ],
        ],
      ),
    );
  }
}
