module Infrastructure
  # Equivalente a @Scheduled de Spring o node-cron: un hilo que despierta cada intervalo y ejecuta
  # la tarea. Ruby no necesita una gema para esto, y el Gemfile se mantiene mínimo.
  #
  # Limitación conocida (ver README): el hilo corre dentro de cada instancia del servicio. Con una
  # sola instancia es correcto; si vacaciones-service se escalara a N réplicas, las N ejecutarían
  # el job y publicarían el mismo evento N veces. La deduplicación de los consumidores reduce el
  # daño pero no evita el trabajo repetido; la solución real es un lock distribuido (Reto 31).
  class Scheduler
    def initialize(interval_seconds:, logger:, &task)
      @interval_seconds = interval_seconds
      @logger = logger
      @task = task
      @thread = nil
    end

    def start
      @thread = Thread.new do
        loop do
          sleep(@interval_seconds)
          run_once
        end
      end
      @logger.info('Vacation scheduler started', intervalSeconds: @interval_seconds)
      self
    end

    def stop
      @thread&.kill
      @thread = nil
    end

    private

    # Un fallo en una pasada no puede matar el hilo: si lo hiciera, el servicio seguiría vivo y
    # sano para Docker, pero ningún período volvería a transicionar en toda la vida del contenedor.
    def run_once
      @task.call
    rescue StandardError => e
      @logger.error('Vacation scheduler run failed', error: e.message)
    end
  end
end
