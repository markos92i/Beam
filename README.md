🌀 NetworkActor
NetworkActor es una librería ligera y robusta para Swift diseñada para gestionar peticiones de red de forma asíncrona y segura. Aprovecha el poder de los Swift Actors para garantizar que la configuración de red y la gestión de estados estén libres de data races.

✨ Características
Thread-Safe por diseño: Construido sobre el modelo de actor de Swift.

Async/Await: Olvídate de los cierres (closures) y el "callback hell".

Genéricos inteligentes: Decodificación automática de JSON a modelos Codable.

Cero dependencias: Utiliza URLSession puro, manteniendo tu proyecto ligero.

Concurrencia estricta: 100% compatible y testada con concurrencia estricta con proyecto en producción.

🚀 Instalación
Swift Package Manager (SPM)
Añade la siguiente URL a tus dependencias de Xcode:
git@gitlab.sngular.com:os3/building-blocks/ios/communications/networkactor.git

🛠️ Uso Básico
1. Definir tu Modelo
Asegúrate de que tu modelo implemente Codable.
Tambien puedes enviar Data puro, y usar multipart/form

Swift
struct User: Codable {
    let id: Int
    let name: String
}
2. Realizar una Petición
Gracias a NetworkActor, puedes realizar peticiones de forma segura desde cualquier lugar de tu app.

Swift
import NetworkActor

struct TestService: ServiceProtocol {
    var service: ServiceManager

    init(id: Int, body: MyModel?) {
        self.service = .init(network: .init(certificates: APIConstants.certificates),
                             auth: AuthManager.shared,
                             crash: CrashManager.shared,
                             api: .init(method: .post,
                                        baseURL: URLs.api,
                                        path: "/yourPath/\(id)",
                                        headers: APIConstants.headers.merging(ContentType.json.header) { $1 },
                                        body: body))
    }
    
    func request() async -> Result<Bool, ServiceError<MyErrorModel>> {
        await service.request()
    }
}

🏗️ Arquitectura Recomendada
Para evitar bloqueos en el hilo de UI (como mencionamos anteriormente), NetworkActor separa la lógica de red del ciclo de vida de la vista.

Ejemplo con SwiftUI
Swift
struct ProfileView: View {
    @State private var user: User?
    private let api = NetworkActor()
    @State private var progress: Progress?

    var body: some View {
        VStack {
            if let user {
                Text("Hola, \(user.name)")
            } else {
                ProgressView(progress) // Feedback visual inmediato
            }
        }
        .task {
            let service = TestService(id: 1, body: MyModel())
            for await p in service.progress.prefix(1) { progress = p }

            switch await service.request() {
            case .success(let result):
                self.user = result
            case .failure(let result):
            }
        }
    }
}
⚠️ ¿Por qué un Actor?
A diferencia de una clase convencional, un actor en Swift:

Aísla el estado: Evita que múltiples hilos modifiquen la configuración de red (tokens, headers) al mismo tiempo.

Optimiza recursos: Gestiona las peticiones de forma eficiente bajo el nuevo modelo de concurrencia de hilos de Apple.
