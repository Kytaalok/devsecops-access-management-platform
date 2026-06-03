from pathlib import Path
p = Path('Jenkinsfile')
s = p.read_text()
old_cmd = '''            pip install --no-cache-dir -r requirements.txt
            mkdir -p ../../reports
            pytest -q --junitxml=../../reports/api-pytest.xml
'''
new_cmd = '''            python -m pip install --no-cache-dir -r requirements.txt
            mkdir -p ../../reports
            PYTHONPATH="$PWD" python -m pytest -q --junitxml=../../reports/api-pytest.xml
'''
old_post = '''        always {
          junit allowEmptyResults: true, testResults: 'reports/api-pytest.xml'
          archiveArtifacts artifacts: 'reports/api-pytest.xml', allowEmptyArchive: true
        }
'''
new_post = '''        always {
          archiveArtifacts artifacts: 'reports/api-pytest.xml', allowEmptyArchive: true
        }
'''
if old_cmd not in s:
    raise SystemExit('command block not found')
if old_post not in s:
    raise SystemExit('post block not found')
s = s.replace(old_cmd, new_cmd).replace(old_post, new_post)
p.write_text(s)
