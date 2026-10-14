package com.poupoutch.cnsnn.data

import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.FirebaseAuthInvalidCredentialsException
import com.google.firebase.auth.FirebaseAuthInvalidUserException
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.auth.FirebaseAuthWeakPasswordException
import com.google.firebase.firestore.FirebaseFirestoreException

/** Errors the app explains itself, with the same French wording as the iPhone app. */
class CloudError(val kind: Kind) : Exception(kind.message) {
    enum class Kind(val message: String) {
        AUTHENTICATION("Connectez-vous avant cette action."),
        PERMANENT_ACCOUNT_CONNECTED("Un compte permanent est déjà connecté. Fermez cette fenêtre pour retrouver votre profil."),
        OFFLINE("Pas de connexion au serveur. Vérifiez le réseau puis réessayez."),
        PROGRESS_TOO_LARGE("Votre historique est trop volumineux pour être synchronisé."),
        DUPLICATE_WORD("Ce mot a déjà été proposé. Essayez-en un autre."),
        PROPOSAL_TOO_SOON("Patientez quelques secondes avant une nouvelle proposition."),
        PROPOSAL_QUOTA("Vous avez atteint la limite de 10 propositions par jour. Revenez demain."),
        ALREADY_REPORTED("Votre signalement est déjà envoyé. Merci !"),
        FRIEND_NOT_FOUND("Aucun joueur n’a ce code. Vérifiez les 6 caractères."),
        FRIEND_IS_YOU("C’est votre propre code. Envoyez-le à vos amis !"),
        GUESS_TOO_SOON("Patientez une seconde avant de réessayer."),
        GUESS_LIMIT("Vous avez utilisé vos 20 essais du jour."),
        DAILY_FINISHED("Votre partie du jour est déjà terminée."),
        SUSPENDED("Votre compte est suspendu : les défis ne sont pas disponibles."),
        CHALLENGE_UNAVAILABLE("Ce défi n’est plus disponible. Mettez l’application à jour si le problème continue."),
    }

    enum class Code { EMAIL_IN_USE, WRONG_CREDENTIALS, WEAK_PASSWORD, INVALID_EMAIL, RECENT_LOGIN, NETWORK, TOO_MANY, PERMISSION_DENIED, UNAVAILABLE, OTHER }

    companion object {
        fun code(error: Throwable): Code = when (error) {
            is FirebaseAuthUserCollisionException -> Code.EMAIL_IN_USE
            is FirebaseAuthWeakPasswordException -> Code.WEAK_PASSWORD
            is FirebaseAuthInvalidCredentialsException ->
                if (error.errorCode == "ERROR_INVALID_EMAIL") Code.INVALID_EMAIL else Code.WRONG_CREDENTIALS
            is FirebaseAuthInvalidUserException -> Code.WRONG_CREDENTIALS
            is FirebaseAuthRecentLoginRequiredException -> Code.RECENT_LOGIN
            is FirebaseNetworkException -> Code.NETWORK
            is FirebaseTooManyRequestsException -> Code.TOO_MANY
            is FirebaseFirestoreException -> when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED -> Code.PERMISSION_DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE, FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> Code.UNAVAILABLE
                else -> Code.OTHER
            }
            else -> Code.OTHER
        }

        /** A short French explanation for any error shown to the player. */
        fun message(error: Throwable): String {
            if (error is CloudError) return error.kind.message
            return when (code(error)) {
                Code.EMAIL_IN_USE -> "Cette adresse a déjà un compte CNSNN. Choisissez « J’ai déjà un compte » pour vous y connecter."
                Code.WRONG_CREDENTIALS -> "Adresse ou mot de passe incorrect."
                Code.WEAK_PASSWORD -> "Choisissez un mot de passe d’au moins 8 caractères."
                Code.INVALID_EMAIL -> "Cette adresse email n’est pas valide."
                Code.RECENT_LOGIN -> "Pour votre sécurité, saisissez à nouveau votre mot de passe."
                Code.NETWORK, Code.UNAVAILABLE -> Kind.OFFLINE.message
                Code.TOO_MANY -> "Trop de tentatives. Réessayez dans quelques minutes."
                Code.PERMISSION_DENIED -> "Action refusée par le serveur. Mettez l’application à jour puis réessayez."
                Code.OTHER -> "Une erreur est survenue. Réessayez."
            }
        }
    }
}
