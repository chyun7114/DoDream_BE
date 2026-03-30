import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
public class BcryptGen {
  public static void main(String[] args) {
    BCryptPasswordEncoder e = new BCryptPasswordEncoder();
    System.out.println("password=" + e.encode("password"));
    System.out.println("seedpass=" + e.encode("seedpass"));
  }
}
