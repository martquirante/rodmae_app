import json
import os

transcript_path = r"C:\Users\martquirante\.gemini\antigravity\brain\9c038532-605e-47e3-afed-68b0a83bd709\.system_generated\logs\transcript.jsonl"

if not os.path.exists(transcript_path):
    print(f"Log path does not exist: {transcript_path}")
    exit(1)

with open(transcript_path, 'r', encoding='utf-8') as f:
    for line in f:
        if '"step_index":513,' in line or '"step_index":513}' in line:
            try:
                obj = json.loads(line)
                calls = obj.get('tool_calls', [])
                for call in calls:
                    if call.get('name') == 'write_to_file':
                        args = call.get('args', {})
                        if isinstance(args, str):
                            args = json.loads(args)
                        code = args.get('CodeContent', '')
                        # Let's clean up double encoding
                        if isinstance(code, str):
                            # Remove surrounding quotes if they are escaped literal quotes
                            if code.startswith('"') and code.endswith('"'):
                                try:
                                    code = json.loads(code)
                                except:
                                    code = code[1:-1]
                            # Replace escaped newlines
                            code = code.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')
                        
                        out_path = r"C:\Users\martquirante\StudioProjects\rodmae_app\scratch\recovered_add_transaction_sheet.dart"
                        with open(out_path, 'w', encoding='utf-8') as out_f:
                            out_f.write(code)
                        print("SUCCESS: Recovered AddTransactionSheet code")
                        exit(0)
            except Exception as e:
                print(f"Error parsing line: {e}")

print("Error: step_index 513 not found or didn't contain write_to_file")
