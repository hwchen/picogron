Switch from while loop to labeled switch:
```
picogron kwtk|🈳 > cat testdata/citylots.gron > /dev/null && poop "zig-out/bin/picogron-old -u testdata/citylots.gron" "zig-out/bin/picogron-new -u testdata/citylots.gron"
Benchmark 1 (5 runs): zig-out/bin/picogron-old -u testdata/citylots.gron
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          1.10s  ± 6.40ms    1.09s  … 1.11s           0 ( 0%)        0%
  peak_rss            777KB ± 1.83KB     774KB …  778KB          1 (20%)        0%
  cpu_cycles         4.52G  ± 27.1M     4.49G  … 4.56G           0 ( 0%)        0%
  instructions       9.90G  ± 12.6      9.90G  … 9.90G           0 ( 0%)        0%
  cache_references   11.3M  ±  226K     11.1M  … 11.7M           0 ( 0%)        0%
  cache_misses        269K  ± 11.1K      256K  …  285K           0 ( 0%)        0%
  branch_misses      9.27M  ± 20.6K     9.26M  … 9.31M           0 ( 0%)        0%
Benchmark 2 (5 runs): zig-out/bin/picogron-new -u testdata/citylots.gron
  measurement          mean ± σ            min … max           outliers         delta
  wall_time          1.02s  ± 2.07ms    1.02s  … 1.02s           0 ( 0%)        ⚡-  7.3% ±  0.6%
  peak_rss            807KB ±    0       807KB …  807KB          0 ( 0%)        💩+  3.8% ±  0.2%
  cpu_cycles         4.17G  ± 10.8M     4.16G  … 4.19G           0 ( 0%)        ⚡-  7.7% ±  0.7%
  instructions       15.0G  ± 7.40      15.0G  … 15.0G           0 ( 0%)        💩+ 51.9% ±  0.0%
  cache_references   12.0M  ±  154K     11.8M  … 12.2M           0 ( 0%)        💩+  6.6% ±  2.5%
  cache_misses        261K  ± 22.1K      228K  …  288K           0 ( 0%)          -  3.0% ±  9.5%
  branch_misses      8.05M  ± 92.6K     7.91M  … 8.11M           0 ( 0%)        ⚡- 13.2% ±  1.1%
```

# ungron, going from popping tail one-by-one to in batch

Can't compare directly to above (labeled switch) because this round includes features
- handle obj/arr not declared on rhs
- nulls in arrays

Big file one-by-one:
```
picogron suvp|🈳 > zig-14 build -Doptimize=ReleaseFast && poop 'picogron -u testdata/citylots.gron'
Benchmark 1 (3 runs): picogron -u testdata/citylots.gron
  measurement          mean ± σ            min … max           outliers
  wall_time          1.99s  ± 54.2ms    1.95s  … 2.05s           0 ( 0%)
  peak_rss            722KB ± 89.9KB     618KB …  774KB          0 ( 0%)
  cpu_cycles         8.51G  ±  239M     8.34G  … 8.78G           0 ( 0%)
  instructions       23.7G  ± 55.6      23.7G  … 23.7G           0 ( 0%)
  cache_references   1.29G  ± 33.4M     1.26G  … 1.33G           0 ( 0%)
  cache_misses       4.86M  ±  713K     4.10M  … 5.51M           0 ( 0%)
  branch_misses      7.98M  ± 26.5K     7.96M  … 8.01M           0 ( 0%)
```

Big file batch:
```
picogron suvp| > zig-14 build -Doptimize=ReleaseFast && poop 'picogron -u testdata/citylots.gron'
Benchmark 1 (4 runs): picogron -u testdata/citylots.gron
  measurement          mean ± σ            min … max           outliers
  wall_time          1.39s  ± 13.0ms    1.38s  … 1.41s           0 ( 0%)
  peak_rss            738KB ± 77.2KB     623KB …  778KB          1 (25%)
  cpu_cycles         5.86G  ± 58.3M     5.82G  … 5.94G           0 ( 0%)
  instructions       20.8G  ± 8.58      20.8G  … 20.8G           0 ( 0%)
  cache_references   12.5M  ±  125K     12.4M  … 12.7M           0 ( 0%)
  cache_misses        212K  ± 32.5K      164K  …  239K           1 (25%)
  branch_misses      8.01M  ± 53.4K     7.93M  … 8.06M           1 (25%)
```

Small file one-by-one:
```
picogron nkzo|🈳 > zig-14 build -Doptimize=ReleaseFast && poop 'picogron -u testdata/highly-nested.gron'
Benchmark 1 (10000 runs): picogron -u testdata/highly-nested.gron
  measurement          mean ± σ            min … max           outliers
  wall_time           387us ± 89.0us     250us …  850us          2 ( 0%)
  peak_rss            778KB ± 7.98KB     623KB …  778KB        135 ( 1%)
  cpu_cycles         29.7K  ±  782      28.2K  … 39.7K         346 ( 3%)
  instructions       15.6K  ± 0.52      15.6K  … 15.6K           0 ( 0%)
  cache_references   6.19K  ±  263      5.49K  … 9.03K         847 ( 8%)
  cache_misses        398   ± 46.5       283   … 1.46K         413 ( 4%)
  branch_misses       122   ± 14.9       101   …  237          854 ( 9%)
```

Small file batch:
```
picogron suvp| > zig-14 build -Doptimize=ReleaseFast && poop 'picogron -u testdata/highly-nested.gron'
Benchmark 1 (10000 runs): picogron -u testdata/highly-nested.gron
  measurement          mean ± σ            min … max           outliers
  wall_time           355us ± 84.3us     238us …  792us          2 ( 0%)
  peak_rss            778KB ± 7.38KB     623KB …  778KB        127 ( 1%)
  cpu_cycles         22.7K  ±  732      21.0K  … 28.3K         300 ( 3%)
  instructions       9.62K  ± 0.52      9.62K  … 9.62K           2 ( 0%)
  cache_references   3.50K  ±  183      3.08K  … 5.34K         223 ( 2%)
  cache_misses        358   ± 32.9       274   …  879          346 ( 3%)
  branch_misses       111   ± 15.5        84   …  216          658 ( 7%)
```
