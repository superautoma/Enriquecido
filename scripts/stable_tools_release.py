"""Archive a user-tested APK, without rebuilding it or moving existing tags."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote

WORKFLOW = '.github/workflows/build-integrated-quill-apk.yml'
ARTIFACT = 'gestor-quill-integrado-apk'
BASELINE_COMMIT = '4c3be14d0cc411c3fd2598dcd88c8ddc2e426264'
PACKAGE_NAME = 'org.gestorherramientas.gestor_herramientas_quill_test'
REQUIRED_STEPS = {
    'Build optimized APK', 'Verify stable APK signature', 'Upload APK',
    'Analyze integrated test', 'Verify layout, startup and voltage persistence',
    'Check Android startup and back navigation',
}


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Repositorio no valido')
        self.repository = repository

    def get(self, path):
        return json.loads(command('gh', 'api', f'repos/{self.repository}/{path}'))

    def post(self, path, data):
        return json.loads(command(
            'gh', 'api', '--method', 'POST', f'repos/{self.repository}/{path}',
            '--input', '-', input=json.dumps(data)))

    def optional(self, path):
        # Check HTTP status, never mistake an auth/network failure for absence.
        result = subprocess.run(
            ['gh', 'api', '--include', f'repos/{self.repository}/{path}'],
            text=True, capture_output=True)
        if result.returncode == 0:
            return json.loads(result.stdout.split('\n\n', 1)[1])
        if re.search(r'^HTTP/\S+ 404\b', result.stdout, re.MULTILINE):
            return None
        raise RuntimeError('No se pudo consultar GitHub: ' + result.stderr.strip())

    def pages(self, path, field):
        separator = '&' if '?' in path else '?'
        for page in range(1, 101):
            response = self.get(f'{path}{separator}per_page=100&page={page}')
            entries = response[field] if field else response
            yield from entries
            if len(entries) < 100:
                return
        raise RuntimeError('Consulta demasiado grande; no se eligio una version por aproximacion')


def tag_commit(api, tag):
    ref = api.optional('git/ref/tags/' + quote(tag, safe=''))
    if ref is None:
        return None
    obj = ref['object']
    for _ in range(10):
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            break
        obj = api.get('git/tags/' + obj['sha'])['object']
    raise RuntimeError('La etiqueta no apunta a un commit verificable')


def plan(api, build_number, confirmed, dry_run):
    if not re.fullmatch(r'[1-9][0-9]*', build_number):
        raise ValueError('Indica el numero de compilacion de la APK, por ejemplo 101')
    if not dry_run and not confirmed:
        raise ValueError('Falta confirmar que esta APK funciona en el movil')
    workflow = api.get('actions/workflows/build-integrated-quill-apk.yml')
    runs = api.pages(f"actions/workflows/{workflow['id']}/runs", 'workflow_runs')
    run = next((r for r in runs if r['run_number'] == int(build_number)), None)
    if run is None:
        raise ValueError('No se encontro esa compilacion de la APK')
    if (run['path'] != WORKFLOW or run['workflow_id'] != workflow['id']
            or run['head_repository']['full_name'] != api.repository
            or run['status'] != 'completed' or run['conclusion'] != 'success'):
        raise ValueError('La compilacion debe haber terminado correctamente en este repositorio')
    jobs = api.pages(
        f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", 'jobs')
    if not any(REQUIRED_STEPS.issubset({s['name'] for s in j['steps']
                                     if s.get('conclusion') == 'success'}) for j in jobs):
        raise ValueError('Faltan pruebas o verificacion de firma satisfactorias')
    artifacts = list(api.pages(f"actions/runs/{run['id']}/artifacts", 'artifacts'))
    candidates = [a for a in artifacts if a['name'] == ARTIFACT]
    if len(candidates) != 1 or candidates[0]['expired']:
        raise ValueError('La APK original no esta disponible o ha caducado; no se recompilara')
    artifact = candidates[0]
    if artifact['workflow_run']['head_sha'] != run['head_sha']:
        raise ValueError('La APK y el codigo fuente no coinciden')
    tag = f'gestor-herramientas-v{build_number}'
    existing = tag_commit(api, tag)
    if existing is not None and existing != run['head_sha']:
        raise ValueError('Esa etiqueta ya apunta a otro commit; no se modificara')
    return {
        'repository': api.repository, 'version': int(build_number), 'tag': tag,
        'commit': run['head_sha'], 'run_id': run['id'],
        'run_attempt': run['run_attempt'], 'run_url': run['html_url'],
        'artifact_id': artifact['id'], 'artifact_digest': artifact.get('digest'),
        'confirmed_by': os.environ.get('GITHUB_ACTOR', ''),
    }


def signer_digest(certificate_output):
    # apksigner may list the same certificate for several Android SDK ranges.
    # Source Stamp certificates are not APK signing certificates.
    digests = re.findall(
        r'^(?:V[1-4](?:\.[0-9]+)? Signer:|'
        r'Signer (?:#[1-9][0-9]*|\(minSdkVersion=[^\r\n]+\)))'
        r' certificate SHA-256 digest:[ \t]*([0-9a-fA-F]{64})[ \t]*$',
        certificate_output, flags=re.MULTILINE)
    unique = {digest.lower() for digest in digests}
    if len(unique) != 1:
        raise RuntimeError('La firma de la APK no se pudo verificar: '
                           'se esperaba un unico certificado de firma')
    return unique.pop()


def verify_apk(api, info, directory):
    apks = list(Path(directory).rglob('*.apk'))
    if len(apks) != 1 or apks[0].name != 'app-release.apk':
        raise ValueError('El artefacto debe contener una sola APK original app-release.apk')
    apk = apks[0]
    root = Path(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', '')))
    signers = list(root.glob('build-tools/*/apksigner'))
    if not signers:
        raise RuntimeError('No se encontro apksigner para verificar la APK')
    signer = max(signers, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
    certificate = command(str(signer), 'verify', '--print-certs', str(apk))
    print('Resultado de apksigner:\n' + certificate)
    digest = signer_digest(certificate)
    if tag_commit(api, 'gestor-herramientas-v101') != BASELINE_COMMIT:
        raise ValueError('La referencia V101 ha cambiado; se cancela')
    key = api.get('contents/.github/dev-signing/android-debug.keystore.b64?ref=' + BASELINE_COMMIT)
    if key.get('encoding') != 'base64':
        raise ValueError('Formato desconocido de la clave estable')
    encoded_key = base64.b64decode(key['content'])
    with tempfile.TemporaryDirectory() as folder:
        key_path = Path(folder) / 'stable.keystore'
        key_path.write_bytes(base64.b64decode(encoded_key))
        key_path.chmod(0o600)
        cert = subprocess.check_output([
            'keytool', '-exportcert', '-keystore', str(key_path),
            '-storepass', 'android', '-alias', 'androiddebugkey'])
    expected = hashlib.sha256(cert).hexdigest()
    if digest != expected:
        raise ValueError('La APK no tiene la firma estable de V101')
    aapt = signer.parent / 'aapt'
    package = command(str(aapt), 'dump', 'badging', str(apk))
    match = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)'", package, re.MULTILINE)
    if not match or match[1] != PACKAGE_NAME or int(match[2]) != info['version']:
        raise ValueError('El identificador o versionCode de la APK no coincide')
    with apk.open('rb') as stream:
        info['apk_sha256'] = hashlib.file_digest(stream, 'sha256').hexdigest()
    info['certificate_sha256'] = expected
    info['package_name'] = match[1]
    return apk


def publish(api, info, apk, dry_run):
    if dry_run:
        return 'Comprobacion correcta. No se han creado etiquetas ni publicaciones.'
    existing = tag_commit(api, info['tag'])
    if existing is not None and existing != info['commit']:
        raise ValueError('La etiqueta ha cambiado; se cancela sin sobrescribirla')
    release = api.optional('releases/tags/' + info['tag'])
    if release is None:
        release = next((r for r in api.pages('releases', None)
                        if r['tag_name'] == info['tag']), None)
    if release and not release['draft']:
        assets = {a['name']: a for a in api.pages(f"releases/{release['id']}/assets", None)}
        expected_apk = f"Gestor_Herramientas_V{info['version']}.apk"
        if expected_apk in assets and 'version-estable.json' in assets:
            # The saved manifest ties an existing release to this exact APK/run.
            with tempfile.TemporaryDirectory() as folder:
                command('gh', 'release', 'download', info['tag'], '--repo', api.repository,
                        '--pattern', 'version-estable.json', '--dir', folder)
                saved = json.loads((Path(folder) / 'version-estable.json').read_text())
            fields = ('commit', 'run_id', 'run_attempt', 'artifact_id', 'apk_sha256')
            if all(saved.get(k) == info.get(k) for k in fields):
                return release['html_url'] + ' (ya guardada; sin cambios)'
        raise ValueError('Ya existe una publicacion diferente o incompleta; no se sobrescribira')
    body = (f"APK V{info['version']} probada y confirmada por {info['confirmed_by']}.\n\n"
            f"Codigo: `{info['commit']}`.\nCompilacion original: {info['run_url']}.\n\n"
            f"SHA-256 de APK: `{info['apk_sha256']}`.\n"
            f"SHA-256 de certificado: `{info['certificate_sha256']}`.\n\n"
            "Se conserva la APK original, sin recompilar. El codigo se descarga en Source code.\n"
            "Los datos SQLite y las fotografias del movil se respaldan desde la aplicacion.")
    if existing is None:
        tag = api.post('git/tags', {
            'tag': info['tag'], 'message': body,
            'object': info['commit'], 'type': 'commit'})
        api.post('git/refs', {'ref': 'refs/tags/' + info['tag'], 'sha': tag['sha']})
    if release is None:
        release = api.post('releases', {
            'tag_name': info['tag'], 'target_commitish': info['commit'],
            'name': f"Gestor de Herramientas V{info['version']} estable",
            'body': body, 'draft': True, 'prerelease': False})
    # Drafts left by a transfer failure can be resumed, only for the same content.
    if release['tag_name'] != info['tag'] or release['body'] != body:
        raise ValueError('Existe un borrador distinto; no se sobrescribira')
    with tempfile.TemporaryDirectory() as folder:
        package = Path(folder)
        apk_name = f"Gestor_Herramientas_V{info['version']}.apk"
        (package / apk_name).write_bytes(apk.read_bytes())
        (package / 'version-estable.json').write_text(json.dumps(info, indent=2) + '\n')
        (package / 'SHA256SUMS.txt').write_text(f"{info['apk_sha256']}  {apk_name}\n")
        assets = {a['name']: a for a in api.pages(f"releases/{release['id']}/assets", None)}
        for path in sorted(package.iterdir()):
            if path.name in assets:
                # Check existing bytes; never use --clobber.
                with tempfile.TemporaryDirectory() as downloaded:
                    command('gh', 'release', 'download', info['tag'], '--repo', api.repository,
                            '--pattern', path.name, '--dir', downloaded)
                    if (Path(downloaded) / path.name).read_bytes() != path.read_bytes():
                        raise ValueError('El borrador contiene otro archivo: ' + path.name)
            else:
                command('gh', 'release', 'upload', info['tag'], str(path), '--repo', api.repository)
    command('gh', 'release', 'edit', info['tag'], '--repo', api.repository,
            '--draft=false', '--latest=false')
    return api.get('releases/tags/' + info['tag'])['html_url']


def main():
    import sys
    api = GitHub(os.environ['GITHUB_REPOSITORY'])
    dry_run = os.environ.get('DRY_RUN', 'true') == 'true'
    confirmed = os.environ.get('CONFIRMED', 'false') == 'true'
    if sys.argv[1:] == ['plan']:
        info = plan(api, os.environ['BUILD_NUMBER'], confirmed, dry_run)
        Path('stable-plan.json').write_text(json.dumps(info, indent=2) + '\n')
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f"run_id={info['run_id']}\nartifact_id={info['artifact_id']}\n")
        print(f"V{info['version']}: {info['commit']}; APK original {info['run_id']}")
    elif sys.argv[1:] == ['save']:
        # Revalidate live metadata immediately before any mutation.
        info = plan(api, os.environ['BUILD_NUMBER'], confirmed, dry_run)
        saved = json.loads(Path('stable-plan.json').read_text())
        if info != saved:
            raise ValueError('La compilacion ha cambiado durante la descarga; se cancela')
        apk = verify_apk(api, info, 'stable-apk')
        result = publish(api, info, apk, dry_run)
        print(result)
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f"V{info['version']} — {result}\n\nCommit: `{info['commit']}`\n")
    else:
        raise SystemExit('Uso: stable_tools_release.py plan|save')


if __name__ == '__main__':
    main()
