eff TodoStorage {
    def getAllTodos(): List[Todo]
    def saveTodos(todos: List[Todo]): Unit
}

mod TodoStorageHandler {
    pub def runWithState(stateRef: Ref[List[Todo], r], f: Unit -> a \ ef): a \ ef - {TodoStorage} + r =
        run {
            f()
        } with handler TodoStorage {
            def getAllTodos(_, resume) = 
                let todos = Ref.get(stateRef);
                resume(todos)
            
            def saveTodos(todos, resume) = {
                Ref.put(todos, stateRef);
                resume()
            }
        }
}