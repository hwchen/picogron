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
