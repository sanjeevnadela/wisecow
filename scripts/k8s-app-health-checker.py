#!/usr/bin/env python3

"""
Kubernetes-Integrated Application Health Checker
Designed to work within Docker containers and Kubernetes environments
Checks both local and cluster-wide application health
"""

import urllib.request
import urllib.error
import time
import sys
import argparse
import json
import os
import subprocess
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import socket

class K8sAppHealthChecker:
    def __init__(self, base_url: str, timeout: int = 10, k8s_mode: bool = False):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.k8s_mode = k8s_mode
        self.namespace = os.environ.get('NAMESPACE', 'default')
        self.app_name = os.environ.get('APP_NAME', 'wisecow')
        
    def check_http_connectivity(self) -> Tuple[bool, str, float]:
        """Check basic HTTP connectivity and response time"""
        try:
            start_time = time.time()
            
            request = urllib.request.Request(
                self.base_url,
                headers={'User-Agent': 'K8sHealthChecker/1.0'}
            )
            
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                response_time = time.time() - start_time
                return True, str(response.status), response_time
                
        except urllib.error.HTTPError as e:
            return True, str(e.code), time.time() - start_time if 'start_time' in locals() else 0.0
        except urllib.error.URLError as e:
            if "timeout" in str(e).lower():
                return False, "TIMEOUT", 0.0
            else:
                return False, f"URL_ERROR: {str(e)}", 0.0
        except Exception as e:
            return False, f"REQUEST_ERROR: {str(e)}", 0.0
    
    def check_k8s_pod_status(self) -> Dict:
        """Check Kubernetes pod status if running in k8s mode"""
        if not self.k8s_mode:
            return {'status': 'NOT_IN_K8S', 'pods': []}
            
        try:
            # Get pod status
            cmd = ['kubectl', 'get', 'pods', '-l', f'app={self.app_name}', 
                   '-n', self.namespace, '-o', 'json']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return {'status': 'KUBECTL_ERROR', 'error': result.stderr}
            
            pod_data = json.loads(result.stdout)
            pods = pod_data.get('items', [])
            
            pod_status = {
                'status': 'SUCCESS',
                'total_pods': len(pods),
                'running_pods': 0,
                'ready_pods': 0,
                'pod_details': []
            }
            
            for pod in pods:
                pod_name = pod['metadata']['name']
                phase = pod['status'].get('phase', 'Unknown')
                ready_condition = False
                
                for condition in pod['status'].get('conditions', []):
                    if condition['type'] == 'Ready' and condition['status'] == 'True':
                        ready_condition = True
                        break
                
                if phase == 'Running':
                    pod_status['running_pods'] += 1
                if ready_condition:
                    pod_status['ready_pods'] += 1
                
                pod_status['pod_details'].append({
                    'name': pod_name,
                    'phase': phase,
                    'ready': ready_condition
                })
            
            return pod_status
            
        except subprocess.TimeoutExpired:
            return {'status': 'TIMEOUT', 'error': 'kubectl command timed out'}
        except json.JSONDecodeError as e:
            return {'status': 'JSON_ERROR', 'error': str(e)}
        except Exception as e:
            return {'status': 'ERROR', 'error': str(e)}
    
    def check_wisecow_functionality(self) -> Dict:
        """Check Wisecow-specific functionality"""
        try:
            request = urllib.request.Request(
                self.base_url,
                headers={'User-Agent': 'WisecowHealthChecker/1.0'}
            )
            
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                content = response.read().decode('utf-8', errors='ignore')
                
                checks = {
                    'http_status': response.status,
                    'response_size': len(content),
                    'content_type': response.headers.get('content-type', 'unknown')
                }
                
                # Check for wisecow-specific content
                content_lower = content.lower()
                checks['fortune_detected'] = 'fortune' in content_lower
                checks['cow_detected'] = 'cow' in content_lower or 'moo' in content_lower
                checks['html_format'] = '<pre>' in content and '</pre>' in content
                
                # Overall functionality assessment
                if (checks['http_status'] == 200 and 
                    checks['fortune_detected'] and 
                    checks['cow_detected'] and 
                    checks['html_format']):
                    checks['functionality'] = 'HEALTHY'
                else:
                    checks['functionality'] = 'DEGRADED'
                
                return checks
                
        except Exception as e:
            return {'functionality': 'FAILED', 'error': str(e)}
    
    def run_comprehensive_check(self) -> Dict:
        """Run all health checks and return comprehensive results"""
        results = {
            'timestamp': datetime.now().isoformat(),
            'base_url': self.base_url,
            'k8s_mode': self.k8s_mode,
            'namespace': self.namespace,
            'app_name': self.app_name,
            'checks': {}
        }
        
        # 1. HTTP Connectivity Check
        print("Checking HTTP connectivity...")
        http_success, http_status, response_time = self.check_http_connectivity()
        results['checks']['http_connectivity'] = {
            'success': http_success,
            'status': http_status,
            'response_time': round(response_time, 3)
        }
        
        # 2. Wisecow Functionality Check
        print("Checking Wisecow functionality...")
        wisecow_check = self.check_wisecow_functionality()
        results['checks']['wisecow_functionality'] = wisecow_check
        
        # 3. Kubernetes checks (if in k8s mode)
        if self.k8s_mode:
            print("Checking Kubernetes pod status...")
            results['checks']['pod_status'] = self.check_k8s_pod_status()
        
        # 4. Overall health assessment
        overall_healthy = (
            results['checks']['http_connectivity']['success'] and
            results['checks']['wisecow_functionality'].get('functionality') == 'HEALTHY'
        )
        
        if self.k8s_mode:
            pod_status = results['checks'].get('pod_status', {})
            if pod_status.get('status') == 'SUCCESS':
                overall_healthy = overall_healthy and pod_status.get('ready_pods', 0) > 0
        
        results['overall_health'] = 'HEALTHY' if overall_healthy else 'UNHEALTHY'
        results['recommendations'] = self._generate_recommendations(results)
        
        return results
    
    def _generate_recommendations(self, results: Dict) -> List[str]:
        """Generate recommendations based on check results"""
        recommendations = []
        
        # HTTP connectivity issues
        if not results['checks']['http_connectivity']['success']:
            recommendations.append("HTTP connectivity failed - check if application is running")
            
        # Wisecow functionality issues
        wisecow_func = results['checks']['wisecow_functionality'].get('functionality')
        if wisecow_func == 'DEGRADED':
            recommendations.append("Wisecow functionality degraded - check fortune/cowsay installation")
        elif wisecow_func == 'FAILED':
            recommendations.append("Wisecow functionality failed - check application logs")
            
        # Response time issues
        response_time = results['checks']['http_connectivity'].get('response_time', 0)
        if response_time > 5.0:
            recommendations.append(f"High response time ({response_time}s) - check application performance")
            
        # Kubernetes-specific recommendations
        if self.k8s_mode:
            pod_status = results['checks'].get('pod_status', {})
            if pod_status.get('status') == 'SUCCESS':
                ready_pods = pod_status.get('ready_pods', 0)
                total_pods = pod_status.get('total_pods', 0)
                if ready_pods == 0:
                    recommendations.append("No ready pods - check pod logs and readiness probes")
                elif ready_pods < total_pods:
                    recommendations.append(f"Only {ready_pods}/{total_pods} pods ready - check failing pods")
            
        return recommendations

def print_results(results: Dict):
    """Print health check results in a formatted way"""
    print("\n" + "="*70)
    print("KUBERNETES APPLICATION HEALTH CHECK REPORT")
    print("="*70)
    print(f"Timestamp: {results['timestamp']}")
    print(f"Application URL: {results['base_url']}")
    print(f"Kubernetes Mode: {results['k8s_mode']}")
    if results['k8s_mode']:
        print(f"Namespace: {results['namespace']}")
        print(f"App Name: {results['app_name']}")
    print(f"Overall Health: {results['overall_health']}")
    print()
    
    # HTTP Connectivity
    http_check = results['checks']['http_connectivity']
    print(f"HTTP Connectivity: {'✓' if http_check['success'] else '✗'}")
    print(f"  Status: {http_check['status']}")
    print(f"  Response Time: {http_check['response_time']}s")
    print()
    
    # Wisecow Functionality
    wisecow_check = results['checks']['wisecow_functionality']
    print("Wisecow Functionality:")
    print(f"  Status: {wisecow_check.get('functionality', 'UNKNOWN')}")
    print(f"  Fortune Detected: {'✓' if wisecow_check.get('fortune_detected') else '✗'}")
    print(f"  Cow Detected: {'✓' if wisecow_check.get('cow_detected') else '✗'}")
    print(f"  HTML Format: {'✓' if wisecow_check.get('html_format') else '✗'}")
    print()
    
    # Kubernetes checks
    if results['k8s_mode']:
        # Pod Status
        pod_status = results['checks'].get('pod_status', {})
        print("Pod Status:")
        if pod_status.get('status') == 'SUCCESS':
            print(f"  Total Pods: {pod_status.get('total_pods', 0)}")
            print(f"  Running Pods: {pod_status.get('running_pods', 0)}")
            print(f"  Ready Pods: {pod_status.get('ready_pods', 0)}")
            for pod in pod_status.get('pod_details', []):
                status_icon = '✓' if pod['ready'] else '✗'
                print(f"    {status_icon} {pod['name']} ({pod['phase']})")
        else:
            print(f"  Status: {pod_status.get('status', 'UNKNOWN')}")
        print()
    
    # Recommendations
    if results['recommendations']:
        print("Recommendations:")
        for i, rec in enumerate(results['recommendations'], 1):
            print(f"  {i}. {rec}")
    else:
        print("Recommendations: No issues detected")
    print()

def main():
    parser = argparse.ArgumentParser(description='Kubernetes-Integrated Application Health Checker')
    parser.add_argument('url', nargs='?', default='http://localhost:4499', 
                       help='Application URL to check (default: http://localhost:4499)')
    parser.add_argument('-t', '--timeout', type=int, default=10, help='Request timeout in seconds')
    parser.add_argument('-k', '--k8s-mode', action='store_true', 
                       help='Enable Kubernetes mode (check pods, services, ingress)')
    parser.add_argument('-n', '--namespace', default='default', 
                       help='Kubernetes namespace (default: default)')
    parser.add_argument('-a', '--app-name', default='wisecow', 
                       help='Application name label (default: wisecow)')
    parser.add_argument('-o', '--output', help='Save results to JSON file')
    parser.add_argument('-q', '--quiet', action='store_true', help='Quiet mode (minimal output)')
    
    args = parser.parse_args()
    
    # Auto-detect k8s mode if kubectl is available and we're in a pod
    k8s_mode = args.k8s_mode
    if not k8s_mode:
        # Check if we're running in a Kubernetes pod
        if os.path.exists('/var/run/secrets/kubernetes.io/serviceaccount/'):
            k8s_mode = True
            print("Kubernetes mode auto-detected (running in pod)")
    
    # Set environment variables for k8s mode
    if k8s_mode:
        os.environ['NAMESPACE'] = args.namespace
        os.environ['APP_NAME'] = args.app_name
    
    checker = K8sAppHealthChecker(args.url, args.timeout, k8s_mode)
    
    if args.quiet:
        # Quiet mode - just show overall status
        results = checker.run_comprehensive_check()
        print(results['overall_health'])
        sys.exit(0 if results['overall_health'] == 'HEALTHY' else 1)
    else:
        # Normal mode - show detailed results
        print(f"Checking application health: {args.url}")
        if k8s_mode:
            print(f"Kubernetes mode enabled (namespace: {args.namespace}, app: {args.app_name})")
        
        results = checker.run_comprehensive_check()
        print_results(results)
        
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(results, f, indent=2)
            print(f"Results saved to: {args.output}")
        
        # Exit with appropriate code
        sys.exit(0 if results['overall_health'] == 'HEALTHY' else 1)

if __name__ == '__main__':
    main()
