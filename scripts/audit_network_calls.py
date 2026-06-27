#!/usr/bin/env python3
import os
import re
import sys

# Script to audit Swift files for potential network API usage (to guarantee offline compliance)

TARGET_PATTERNS = [
    (r'\bURLSession\b', "Use of URLSession for network requests"),
    (r'\bURLRequest\b', "Use of URLRequest for network configurations"),
    (r'\bNWConnection\b', "Network framework socket connection"),
    (r'\bnw_connection_create\b', "C-level Network framework socket connection"),
    (r'\bSocket\b', "Low-level socket APIs"),
    (r'\"http(s)?://', "Hardcoded HTTP/S URL strings (potential network leaks)")
]

def scan_file(filepath):
    violations = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line_no, line in enumerate(f, 1):
                # Ignore comments
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*') or stripped.startswith('/*'):
                    continue
                
                for pattern, desc in TARGET_PATTERNS:
                    if re.search(pattern, line):
                        violations.append((line_no, line.strip(), desc))
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
    return violations

def main():
    if len(sys.argv) < 2:
        print("Usage: audit_network_calls.py <directory_to_scan>")
        sys.exit(1)
        
    scan_dir = sys.argv[1]
    if not os.path.exists(scan_dir):
        print(f"Directory not found: {scan_dir}")
        sys.exit(1)

    print(f"=== Starting Network Compliance Audit in {scan_dir} ===")
    total_files = 0
    total_violations = 0
    
    for root, _, files in os.walk(scan_dir):
        # Skip package resolved files or build artifacts
        if '.build' in root or '.git' in root or 'tests' in root.lower() or 'MainApp' in root:
            continue
            
        for file in files:
            if file.endswith('.swift'):
                total_files += 1
                filepath = os.path.join(root, file)
                violations = scan_file(filepath)
                if violations:
                    print(f"\n[VIOLATION] File: {filepath}")
                    for line_no, content, desc in violations:
                        print(f"  Line {line_no}: {content}")
                        print(f"    Reason: {desc}")
                        total_violations += 1

    print("\n=== Audit Summary ===")
    print(f"Total Swift files scanned: {total_files}")
    print(f"Total potential network references found: {total_violations}")
    if total_violations > 0:
        print("WARNING: Network references found. Ensure these are not used inside the Keyboard Extension target.")
    else:
        print("SUCCESS: No network API usage detected. Extension complies with strict offline policy.")

if __name__ == "__main__":
    main()
