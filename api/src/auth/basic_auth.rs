pub async fn pam_authenticate(service: &str, user: &str, pass: &str) -> bool {
    let service = service.to_owned();
    let user = user.to_owned();
    let pass = pass.to_owned();
    tokio::task::spawn_blocking(move || {
        let Ok(mut client) = pam::Client::with_password(&service) else {
            return false;
        };
        client.conversation_mut().set_credentials(&user, &pass);
        client.authenticate().is_ok()
    })
    .await
    .unwrap_or(false)
}
