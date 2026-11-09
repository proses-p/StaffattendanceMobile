# Attendance record and tracking
The staff attendance system its a project which is implemented with frontend(flutter) and backend(laravel)
## functionalities
1.allow staff to register there accounts
2.allows super admin to send invitations to other admin and register companies
3. allows admins to send invitation to the staff members
4. allows recording the staff attendance for both check in and check out in the office.
5. tracks the distance and location through geoloacation and geofencing.

## API connection

The app uses `http://127.0.0.1:8000/api/v1` on desktop and
`http://192.168.100.32:8000/api/v1` on Android/iOS by default. Start the Laravel
development server on the PC with `php artisan serve --host=0.0.0.0 --port=8000`.
The phone must be able to reach the PC directly over the network; guest Wi-Fi,
client isolation, or a VPN can prevent that even when the server is listening.

Override the API URL for a different LAN address or deployment with the
compile-time `API_BASE_URL` setting, including `/api/v1` and no trailing slash:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.100.32:8000/api/v1
```

Android cleartext HTTP is enabled only in the debug manifest for local
development. Release builds should use an HTTPS API URL, supplied with the same
`--dart-define` setting when building.

## Field operations

Open **Field Mode** from the **More** navigation section to clock field
sessions and record client visits. Actions are written to the local SQLite
outbox before they are displayed as saved, then synchronized in signed batches
when the app is running and connectivity is available. The app does not
guarantee background synchronization after it is force-closed.

Field records remain separate from office attendance. Signed synchronization
uses the existing approved Android device key. iOS supports the local queue,
location capture, and trusted clock, but this repository has no iOS device
signer/approval path; queued iOS events cannot be submitted until that existing
security capability is available on iOS.

### Field expenses

The Field Mode clock-out flow offers staff the option to record one or more
expenses before continuing clock-out. Expense claims are saved in the existing
SQLite database and synchronized to `/api/v1/field/expenses` when connectivity
is available. A failed expense upload remains available in **My expenses** for
inspection and retry; it does not stop field event synchronization.

Receipt images are copied to an application-private support directory and
retained until the server confirms the upload. These local image files are not
encrypted by the app. Receipt uploads are optional and do not prevent
clock-out.