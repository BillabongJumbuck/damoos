#!/usr/bin/env python3

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: GPL-2.0
# Modified for Android by DAMOOS Android Port

import random
import numpy as np
import subprocess
import time
import argparse
import os
import sys

class AndroidSystem:
    """Q-Learning environment for Android DAMON optimization"""
    
    def __init__(self, damoos_path, workload):
        self.path = damoos_path
        self.workload = workload
        self.pid = 0
        
        # Source adb_interface functions
        self.adb_interface = self.path + "/adb_interface"
        
        # Bash command prefix to source all necessary ADB scripts
        self.bash_prefix = f"source {self.adb_interface}/adb_utils.sh && source {self.adb_interface}/adb_workload.sh && source {self.adb_interface}/adb_metric_collector.sh && source {self.adb_interface}/adb_damon_control.sh && "
        
        print(f"Finding original RSS, refault rate, and PSI pressure of {self.workload}")
        
        # Run workload 3 times to get baseline metrics
        rss_samples = []
        refault_samples = []
        psi_samples = []
        
        for i in range(3):
            print(f"  Baseline run {i+1}/3...")
            
            # Start Android app
            ret = subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}start_android_app {self.workload}"
            ])
            
            if ret != 0:
                print(f"Error: Failed to start {self.workload}")
                sys.exit(1)
            
            # Get PID
            result = subprocess.check_output([
                "bash", "-c",
                f"source {self.adb_interface}/adb_workload.sh && get_app_pid {self.workload}"
            ])
            pid = result.decode().strip()
            
            if not pid:
                print(f"Error: Could not get PID for {self.workload}")
                sys.exit(1)
            
            print(f"    PID: {pid}")
            
            # Collect metrics for 30 seconds
            print("    Collecting metrics...")
            
            # Collect RSS, refault rate, and PSI
            subprocess.Popen([
                "bash", "-c",
                f"{self.bash_prefix}start_remote_collector rss {pid}"
            ])
            
            subprocess.Popen([
                "bash", "-c",
                f"{self.bash_prefix}start_remote_collector refault {pid}"
            ])
            
            subprocess.Popen([
                "bash", "-c",
                f"{self.bash_prefix}start_remote_collector psi {pid}"
            ])
            
            # Wait 30 seconds
            time.sleep(30)
            
            # Stop collectors
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}stop_remote_collector rss {pid}"
            ])
            
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}stop_remote_collector refault {pid}"
            ])
            
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}stop_remote_collector psi {pid}"
            ])
            
            # Pull data
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}pull_metric_data rss {pid} {self.path}/results"
            ])
            
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}pull_metric_data refault {pid} {self.path}/results"
            ])
            
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}pull_metric_data psi {pid} {self.path}/results"
            ])
            
            # Calculate RSS average
            rss_file = f"{self.path}/results/rss/{pid}.stat"
            if os.path.exists(rss_file):
                with open(rss_file, 'r') as f:
                    rss_values = [float(line.strip()) for line in f if line.strip()]
                    if rss_values:
                        rss_avg = sum(rss_values) / len(rss_values)
                        rss_samples.append(rss_avg)
                        print(f"    RSS average: {rss_avg:.0f} KB")
            
            # Calculate refault rate average
            refault_file = f"{self.path}/results/refault/{pid}.stat"
            if os.path.exists(refault_file):
                with open(refault_file, 'r') as f:
                    refault_values = [float(line.strip()) for line in f if line.strip()]
                    if refault_values:
                        refault_avg = sum(refault_values) / len(refault_values)
                        refault_samples.append(refault_avg)
                        print(f"    Refault rate: {refault_avg:.0f} pages/s")
            
            # Calculate PSI pressure average
            psi_file = f"{self.path}/results/psi/{pid}.stat"
            if os.path.exists(psi_file):
                with open(psi_file, 'r') as f:
                    lines = [line.strip() for line in f if line.strip()]
                    # Skip header line
                    if lines and lines[0].startswith('timestamp'):
                        lines = lines[1:]
                    
                    if len(lines) >= 2:
                        # Parse first and last line to get total delta
                        # Format: timestamp some_avg10 some_avg60 some_avg300 some_total ...
                        first_parts = lines[0].split()
                        last_parts = lines[-1].split()
                        
                        if len(first_parts) >= 5 and len(last_parts) >= 5:
                            first_total = float(first_parts[4])  # some_total
                            last_total = float(last_parts[4])
                            first_time = float(first_parts[0])
                            last_time = float(last_parts[0])
                            
                            # Calculate pressure per second (microseconds -> seconds)
                            time_diff = max(last_time - first_time, 1)
                            psi_avg = (last_total - first_total) / time_diff  # μs/s
                            psi_samples.append(psi_avg)
                            print(f"    PSI pressure: {psi_avg:.0f} μs/s")
            
            # Stop app
            subprocess.call([
                "bash", "-c",
                f"{self.bash_prefix}stop_android_app {self.workload}"
            ])
            
            time.sleep(3)  # Wait before next run
        
        # Calculate baseline metrics
        if rss_samples:
            self.orig_rss = sum(rss_samples) / len(rss_samples)
            print(f"\nOriginal RSS: {self.orig_rss:.0f} KB")
        else:
            print("Error: No RSS samples collected")
            sys.exit(1)
        
        if refault_samples:
            self.orig_refault = sum(refault_samples) / len(refault_samples)
            print(f"Original Refault Rate: {self.orig_refault:.0f} pages/s")
        else:
            print("Error: No refault samples collected")
            sys.exit(1)
        
        if psi_samples:
            self.orig_psi = sum(psi_samples) / len(psi_samples)
            print(f"Original PSI Pressure: {self.orig_psi:.0f}\n")
        else:
            print("Warning: No PSI samples collected, using default")
            self.orig_psi = 0  # Default if PSI not available
        
        # For Android apps, we optimize RSS, refault rate, and PSI pressure
        self.orig_runtime = 30.0  # Fixed collection period
    
    def reset(self):
        """Start a new episode - launch app and return initial state"""
        # Start Android app
        ret = subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}start_android_app {self.workload}"
        ])
        
        if ret == 0:
            # Get PID
            result = subprocess.check_output([
                "bash", "-c",
                f"{self.bash_prefix}get_app_pid {self.workload}"
            ])
            self.pid = result.decode().strip()
            print(f"Started {self.workload}, PID: {self.pid}")
        else:
            print(f"Error starting {self.workload}")
            self.pid = None
        
        return np.array(0)
    
    def get_action(self, action):
        """Convert action index to (min_size_KB, min_age_s)"""
        # Actions: {min_age:3s,5s,7s,9s,11s,13s} × {min_size:4KB,8KB,12KB,16KB,20KB}
        # Total: 6 × 5 = 30 actions
        age_idx = action // 5
        size_idx = action % 5
        
        min_age = 2 * age_idx + 3  # 3, 5, 7, 9, 11, 13
        min_size = 4 * size_idx + 4  # 4, 8, 12, 16, 20
        
        return min_size, min_age
    
    def step(self, action):
        """Apply DAMON scheme and collect metrics"""
        if not self.pid:
            print("Error: No active PID")
            return np.array(-100), np.array(100), True
        
        min_size, min_age = self.get_action(action)
        print(f"  Testing scheme: min_size={min_size}K, min_age={min_age}s (action {action})")
        
        # Initialize DAMON
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}damon_init"
        ])
        
        # Set target
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}damon_set_target {self.pid}"
        ])
        
        # Set scheme
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}damon_set_scheme {min_size}K max 0 0 {min_age}s max pageout"
        ])
        
        # Start DAMON
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}damon_start"
        ])
        
        # Start metric collectors (RSS, refault, and PSI)
        subprocess.Popen([
            "bash", "-c",
            f"{self.bash_prefix}start_remote_collector rss {self.pid}"
        ])
        
        subprocess.Popen([
            "bash", "-c",
            f"{self.bash_prefix}start_remote_collector refault {self.pid}"
        ])
        
        subprocess.Popen([
            "bash", "-c",
            f"{self.bash_prefix}start_remote_collector psi {self.pid}"
        ])
        
        # Wait for 30 seconds
        time.sleep(30)
        
        # Stop DAMON
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}damon_stop"
        ])
        
        # Stop collectors
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}stop_remote_collector rss {self.pid}"
        ])
        
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}stop_remote_collector refault {self.pid}"
        ])
        
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}stop_remote_collector psi {self.pid}"
        ])
        
        # Pull data
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}pull_metric_data rss {self.pid} {self.path}/results"
        ])
        
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}pull_metric_data refault {self.pid} {self.path}/results"
        ])
        
        subprocess.call([
            "bash", "-c",
            f"{self.bash_prefix}pull_metric_data psi {self.pid} {self.path}/results"
        ])
        
        # Calculate metrics (RSS, refault rate, and PSI)
        rss_file = f"{self.path}/results/rss/{self.pid}.stat"
        refault_file = f"{self.path}/results/refault/{self.pid}.stat"
        psi_file = f"{self.path}/results/psi/{self.pid}.stat"
        
        rss = self.orig_rss
        refault = self.orig_refault
        psi = self.orig_psi
        
        if os.path.exists(rss_file):
            with open(rss_file, 'r') as f:
                rss_values = [float(line.strip()) for line in f if line.strip()]
                if rss_values:
                    rss = sum(rss_values) / len(rss_values)
        
        if os.path.exists(refault_file):
            with open(refault_file, 'r') as f:
                refault_values = [float(line.strip()) for line in f if line.strip()]
                if refault_values:
                    refault = sum(refault_values) / len(refault_values)
        
        if os.path.exists(psi_file):
            with open(psi_file, 'r') as f:
                lines = [line.strip() for line in f if line.strip()]
                # Skip header line
                if lines and lines[0].startswith('timestamp'):
                    lines = lines[1:]
                
                if len(lines) >= 2:
                    # Parse first and last line to get total delta
                    first_parts = lines[0].split()
                    last_parts = lines[-1].split()
                    
                    if len(first_parts) >= 5 and len(last_parts) >= 5:
                        first_total = float(first_parts[4])  # some_total
                        last_total = float(last_parts[4])
                        first_time = float(first_parts[0])
                        last_time = float(last_parts[0])
                        
                        # Calculate pressure per second (microseconds -> seconds)
                        time_diff = max(last_time - first_time, 1)
                        psi = (last_total - first_total) / time_diff  # μs/s
        
        # Calculate overhead
        rss_overhead = ((rss - self.orig_rss) / self.orig_rss) * 100
        refault_overhead = ((refault - self.orig_refault) / max(self.orig_refault, 1)) * 100
        psi_overhead = ((psi - self.orig_psi) / max(self.orig_psi, 1)) * 100 if self.orig_psi > 0 else 0
        
        print(f"    RSS: {rss:.0f}KB (overhead: {rss_overhead:+.2f}%)")
        print(f"    Refault: {refault:.0f} pages/s (overhead: {refault_overhead:+.2f}%)")
        print(f"    PSI pressure: {psi:.0f} (overhead: {psi_overhead:+.2f}%)")
        
        # Reward function: PSI pressure (50%), refault rate (30%), RSS (20%)
        # Lower overhead is better for all metrics
        # Heavily penalize PSI pressure and refault increases
        score = -(psi_overhead * 0.5 + refault_overhead * 0.3 + rss_overhead * 0.2)
        print(f"    Score: {score:.2f}")
        
        # Stop app
        subprocess.call([
            "bash", "-c",
            f"source {self.adb_interface}/adb_workload.sh && stop_android_app {self.workload}"
        ])
        
        time.sleep(3)  # Cool down
        
        return np.array(score), np.array(int(rss_overhead)), True


def state_to_index(state):
    """Convert RSS overhead to state index"""
    # States: 0%:-4%, -5%:-9%, -10%:-14%.....-95%:-99%, >0%
    if state > 0:
        return 20
    return min(int(-(state / 5)), 19)


def main():
    parser = argparse.ArgumentParser(description='Q-Learning DAMON optimizer for Android')
    parser.add_argument("workload", help="Android app name (e.g., douyin, wechat)")
    parser.add_argument("-n", "--num_iterations", type=int, default=50, 
                       help="Number of training iterations (default: 50)")
    parser.add_argument("-lr", "--learning_rate", type=float, default=0.2,
                       help="Learning rate (default: 0.2)")
    parser.add_argument("-e", "--epsilon", type=float, default=0.2,
                       help="Exploration rate (default: 0.2)")
    parser.add_argument("-d", "--discount", type=float, default=0.9,
                       help="Discount factor (default: 0.9)")
    args = parser.parse_args()
    
    # Get DAMOOS path
    damoos_path = os.environ.get('DAMOOS', os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    
    print("=" * 70)
    print("DAMOOS Q-Learning Optimizer for Android")
    print("=" * 70)
    print(f"Workload: {args.workload}")
    print(f"Iterations: {args.num_iterations}")
    print(f"Learning rate: {args.learning_rate}")
    print(f"Epsilon: {args.epsilon}")
    print(f"Discount: {args.discount}")
    print("=" * 70)
    print()
    
    # 21 states: rss overhead ranges
    num_states = 21
    
    # 30 actions: 6 ages × 5 sizes
    num_actions = 30
    
    # Initialize Q-Table
    Qvalue = np.random.rand(num_states, num_actions)
    
    # Initialize system
    system = AndroidSystem(damoos_path, args.workload)
    
    print("\n" + "=" * 70)
    print("Starting Q-Learning Training")
    print("=" * 70)
    
    # Training loop
    for i in range(args.num_iterations):
        print(f"\nIteration {i+1}/{args.num_iterations}")
        state = system.reset()
        rew = 0
        done = False
        
        while not done:
            # Epsilon-greedy action selection
            if random.uniform(0, 1) >= args.epsilon:
                # Exploit: choose best action
                action = Qvalue[state_to_index(state)].argmax()
            else:
                # Explore: random action
                action = random.randint(0, num_actions - 1)
            
            reward, nextstate, done = system.step(action)
            
            if done:
                print(f"  → Iteration {i+1} reward: {reward:.2f}")
            
            rew += reward
            
            # Q-Learning update
            nxtlist = Qvalue[state_to_index(nextstate)]
            currval = Qvalue[state_to_index(state)][action]
            Qvalue[state_to_index(state)][action] = currval + args.learning_rate * (
                reward + args.discount * max(nxtlist) - currval
            )
            
            state = nextstate
    
    # Save Q-values
    results_dir = os.path.join(damoos_path, "results", "simple_rl_android")
    os.makedirs(results_dir, exist_ok=True)
    
    qvalue_file = os.path.join(results_dir, f"qvalue-{args.workload}.txt")
    np.savetxt(qvalue_file, Qvalue, fmt='%.6f')
    print(f"\nQ-values saved to: {qvalue_file}")
    
    # Evaluation
    print("\n" + "=" * 70)
    print("Final Evaluation (5 runs)")
    print("=" * 70)
    
    eval_rewards = []
    for i in range(5):
        print(f"\nEvaluation run {i+1}/5")
        state = system.reset()
        done = False
        
        while not done:
            # Always exploit during evaluation
            action = Qvalue[state_to_index(state)].argmax()
            min_size, min_age = system.get_action(action)
            print(f"  Best action: min_size={min_size}K, min_age={min_age}s")
            
            reward, nextstate, done = system.step(action)
            
            if done:
                eval_rewards.append(reward)
                print(f"  → Evaluation {i+1} reward: {reward:.2f}")
            
            state = nextstate
    
    avg_reward = sum(eval_rewards) / len(eval_rewards)
    print("\n" + "=" * 70)
    print(f"Average Evaluation Reward: {avg_reward:.2f}")
    print("=" * 70)
    
    # Find and display best scheme
    print("\nBest DAMON scheme found:")
    best_action = Qvalue[0].argmax()  # Assume state 0 (no overhead) as reference
    min_size, min_age = system.get_action(best_action)
    print(f"  min_size: {min_size}K")
    print(f"  min_age: {min_age}s")
    print(f"  action: pageout")
    print(f"  Expected improvement: {-avg_reward:.2f}%")
    print()


if __name__ == '__main__':
    main()
