import XCTest

final class YozhkaFlowTests: XCTestCase {
    private var suiteName: String?

    override func tearDown() {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        YozhkaStubURLProtocol.responder = nil
        super.tearDown()
    }

    func testLoginSendsMailAndPassword() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            return (200, Data(#"{"accessToken":"access","refreshToken":"refresh","mail":"leo@yandex.ru","fullName":"Leo"}"#.utf8))
        }
        let session = try await makeYozhkaClient().login(mail: "leo@yandex.ru", password: "secret")
        XCTAssertEqual(session.accessToken, "access")
        XCTAssertEqual(session.fullName, "Leo")
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/backend/auth/login")
        let body = try JSONDecoder().decode(LoginPayload.self, from: request.body)
        XCTAssertEqual(body.mail, "leo@yandex.ru")
        XCTAssertEqual(body.password, "secret")
        XCTAssertEqual(body.deviceType, "web")
    }

    func testWrongPasswordAsksToSignInAgain() async throws {
        YozhkaStubURLProtocol.responder = { _ in (401, Data()) }
        let model = await model()
        await model.signIn(mail: "leo@yandex.ru", password: "nope")
        let error = await model.lastError
        XCTAssertEqual(error, "Неверный логин или пароль")
        let loggedIn = await model.isLoggedIn
        XCTAssertFalse(loggedIn)
    }

    func testWorkspacePagesKeepClosedSpacesAndStartAtPageOne() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            let page = queryItems(request.url ?? YozhkaClient.site)["page"]
            if page == "2" {
                return (200, Data(#"{"content":[{"id":9,"title":"Сад","code":"garden","closeTs":null}],"totalPages":2}"#.utf8))
            }
            return (200, Data(#"""
            {"content":[
              {"id":4,"title":"Дом","code":"home","closeTs":"2020-01-01T00:00:00","subscription":{"plan":"free"}},
              {"id":"8","title":"   ","code":"work","closeTs":null}
            ],"totalPages":2,"pageNumber":1,"elementsOnPage":2,"totalElements":3}
            """#.utf8))
        }
        let places = try await makeYozhkaClient(accessToken: "access", refreshToken: "refresh").workspaces()
        XCTAssertEqual(places.map(\.id), [4, 8, 9])
        XCTAssertEqual(places.map(\.title), ["Дом", "work", "Сад"])
        XCTAssertEqual(log.requests.map { queryItems($0.url)["page"] }, ["1", "2"])
        XCTAssertTrue(log.requests.allSatisfy { queryItems($0.url)["size"] == "24" })
        XCTAssertTrue(log.requests.allSatisfy { $0.url.path == "/backend/workspace/my" })
        XCTAssertFalse(log.requests.contains { queryItems($0.url)["page"] == "0" })
    }

    func testProjectsUseWorkspaceId() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            return (200, Data(#"{"content":[{"id":15,"workspaceId":4,"title":"Канбан","code":"board","closeTs":null}],"totalPages":1}"#.utf8))
        }
        let places = try await makeYozhkaClient(accessToken: "access", refreshToken: "refresh").projects(workspaceID: 4)
        XCTAssertEqual(places.map(\.title), ["Канбан"])
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.url.path, "/backend/project/tiles/my")
        XCTAssertEqual(queryItems(request.url)["workspaceId"], "4")
        XCTAssertEqual(queryItems(request.url)["page"], "1")
        XCTAssertEqual(queryItems(request.url)["size"], "24")
    }

    func testMissingPlaceIdReportsTheFields() async {
        YozhkaStubURLProtocol.responder = { _ in
            (200, Data(#"{"content":[{"title":"Без id","code":"x"}],"totalPages":1}"#.utf8))
        }
        do {
            _ = try await makeYozhkaClient(accessToken: "access", refreshToken: "refresh").workspaces()
            XCTFail("Ожидалась ошибка разбора")
        } catch let error as YozhkaError {
            guard case let .badStatus(code, message) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(code, 200)
            XCTAssertTrue(message.contains("code"))
            XCTAssertTrue(message.contains("title"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testExpiredAccessRefreshesOnce() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, Data(#"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
                return (401, Data())
            }
            return (200, Data(#"{"content":[{"id":4,"title":"Дом","code":"home"}],"totalPages":1}"#.utf8))
        }
        let client = makeYozhkaClient(accessToken: "old-access", refreshToken: "old-refresh")
        let places = try await client.workspaces()
        XCTAssertEqual(places.map(\.title), ["Дом"])
        let tokens = await client.tokens()
        XCTAssertEqual(tokens.access, "new-access")
        XCTAssertEqual(tokens.refresh, "new-refresh")
        XCTAssertEqual(log.requests.map(\.url.path), [
            "/backend/workspace/my",
            "/backend/auth/refresh",
            "/backend/workspace/my"
        ])
        XCTAssertEqual(log.requests[2].authorization, "Bearer new-access")
    }

    func testTasksKeepStatusDeadlineAndBoardLink() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            return (200, Data(#"""
            {"content":[
              {"id":3,"title":" Купить ","code":"T-1","isCompleted":false,"deadlineTs":"2026-10-28","statusName":"В работе"},
              {"id":4,"title":" ","code":"T-2","isCompleted":true,"deadlineTs":null,"statusName":null}
            ],"totalPages":1}
            """#.utf8))
        }
        let tasks = try await makeYozhkaClient(accessToken: "access", refreshToken: "refresh").tasks(projectID: 15, projectCode: "board")
        XCTAssertEqual(tasks.map(\.title), ["Купить", "T-2"])
        XCTAssertEqual(tasks.map(\.done), [false, true])
        XCTAssertEqual(tasks[0].due, "2026-10-28")
        XCTAssertEqual(tasks[0].status, "В работе")
        XCTAssertEqual(tasks[0].url, "https://yozhka.lukit.ru/project/board")
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.url.path, "/backend/task/15/list")
        XCTAssertEqual(queryItems(request.url)["page"], "1")
    }

    func testSignInSelectsTheOnlySpaceAndBoard() async throws {
        YozhkaStubURLProtocol.responder = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/login") {
                return (200, Data(#"{"accessToken":"access","refreshToken":"refresh","mail":"leo@yandex.ru","fullName":"Leo"}"#.utf8))
            }
            if path.hasSuffix("/workspace/my") {
                return (200, Data(#"{"content":[{"id":4,"title":"Дом","code":"home","closeTs":null}],"totalPages":1}"#.utf8))
            }
            if path.hasSuffix("/project/tiles/my") {
                return (200, Data(#"{"content":[{"id":15,"title":"Канбан","code":"board","closeTs":null}],"totalPages":1}"#.utf8))
            }
            return (200, Data(#"""
            {"content":[{"id":3,"title":"Купить","isCompleted":false,"deadlineTs":null,"statusName":"Новая"}],"totalPages":1}
            """#.utf8))
        }
        let model = await model()
        await model.signIn(mail: "leo@yandex.ru", password: "secret")
        let workspaceID = await model.workspaceID
        let projectID = await model.projectID
        let titles = await model.tasks.map(\.title)
        let error = await model.lastError
        XCTAssertEqual(workspaceID, 4)
        XCTAssertEqual(projectID, 15)
        XCTAssertEqual(titles, ["Купить"])
        XCTAssertNil(error)
        let connected = await model.isConnected
        XCTAssertTrue(connected)
    }

    func testSeveralSpacesStayUnselectedUntilTheUserChooses() async throws {
        YozhkaStubURLProtocol.responder = { request in
            if request.url?.path.hasSuffix("/auth/login") == true {
                return (200, Data(#"{"accessToken":"access","refreshToken":"refresh","mail":"leo@yandex.ru"}"#.utf8))
            }
            return (200, Data(#"""
            {"content":[
              {"id":4,"title":"Дом","code":"home"},
              {"id":5,"title":"Работа","code":"work"}
            ],"totalPages":1}
            """#.utf8))
        }
        let model = await model()
        await model.signIn(mail: "leo@yandex.ru", password: "secret")
        let workspaceID = await model.workspaceID
        let count = await model.workspaces.count
        XCTAssertNil(workspaceID)
        XCTAssertEqual(count, 2)
        await model.selectWorkspace(5)
        let selected = await model.workspaceTitle
        XCTAssertEqual(selected, "Работа")
    }

    func testEmptyCatalogExplainsWhyNothingCanBeChosen() async throws {
        YozhkaStubURLProtocol.responder = { request in
            if request.url?.path.hasSuffix("/auth/login") == true {
                return (200, Data(#"{"accessToken":"access","refreshToken":"refresh","mail":"leo@yandex.ru"}"#.utf8))
            }
            return (200, Data(#"{"content":[],"totalPages":1,"totalElements":0}"#.utf8))
        }
        let model = await model()
        await model.signIn(mail: "leo@yandex.ru", password: "secret")
        let error = await model.lastError
        XCTAssertEqual(error, "Ёжка не вернула ни одного пространства")
    }

    func testServerMessageStaysVisible() async throws {
        YozhkaStubURLProtocol.responder = { request in
            if request.url?.path.hasSuffix("/auth/login") == true {
                return (200, Data(#"{"accessToken":"access","refreshToken":"refresh","mail":"leo@yandex.ru"}"#.utf8))
            }
            return (500, Data(#"{"message":"~~DB-2201X invalid_row_count_in_result_offset_clause"}"#.utf8))
        }
        let model = await model()
        await model.signIn(mail: "leo@yandex.ru", password: "secret")
        let error = await model.lastError
        XCTAssertEqual(error, "~~DB-2201X invalid_row_count_in_result_offset_clause")
        let loggedIn = await model.isLoggedIn
        XCTAssertTrue(loggedIn)
    }

    func testColumnsKeepBoardOrderAndSkipClosedOnes() async throws {
        let log = RequestLog()
        YozhkaStubURLProtocol.responder = { request in
            log.add(request)
            return (200, Data(#"""
            [
              {"id":2,"name":"В работе","nameM":"В работе","orderNum":2,"closeTs":null,"statusColor":"#54b2bc"},
              {"id":1,"name":"Новые","orderNum":1,"closeTs":null},
              {"id":9,"name":"Архив","orderNum":9,"closeTs":"2020-01-01T00:00:00"}
            ]
            """#.utf8))
        }
        let columns = try await makeYozhkaClient(accessToken: "access", refreshToken: "refresh").columns(projectID: 15)
        XCTAssertEqual(columns.map(\.title), ["Новые", "В работе"])
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.url.path, "/backend/workflowStatusesAvail")
        XCTAssertEqual(queryItems(request.url)["projectId"], "15")
    }

    func testSelectedColumnFiltersTheWidget() async {
        let model = await model()
        await MainActor.run {
            model.tasks = [
                TaskItem(id: "1", title: "Новая", done: false, statusID: 1),
                TaskItem(id: "2", title: "В работе", done: false, statusID: 2)
            ]
            model.columns = [
                YozhkaColumn(id: 1, title: "Новые", order: 1),
                YozhkaColumn(id: 2, title: "В работе", order: 2)
            ]
            model.selectColumn(2)
        }
        let titles = await model.visibleTasks.map(\.title)
        let heading = await model.heading
        XCTAssertEqual(titles, ["В работе"])
        XCTAssertEqual(heading, "Ёжка")
        await MainActor.run { model.projectTitle = "HomeHub" }
        let named = await model.heading
        XCTAssertEqual(named, "HomeHub · В работе")
    }

    func testCompletedTasksCanBeHidden() async {
        let model = await model()
        await MainActor.run {
            model.tasks = [
                TaskItem(id: "1", title: "Открытая", done: false),
                TaskItem(id: "2", title: "Готовая", done: true)
            ]
            model.showCompleted = false
        }
        let titles = await model.visibleTasks.map(\.title)
        XCTAssertEqual(titles, ["Открытая"])
    }

    private func model() async -> AppModel {
        let name = "vidgetyo.tests.\(UUID().uuidString)"
        suiteName = name
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let client = makeYozhkaClient()
        return await MainActor.run {
            AppModel(defaults: defaults, client: client)
        }
    }
}

private struct LoginPayload: Decodable {
    var mail: String
    var password: String
    var deviceType: String
}
